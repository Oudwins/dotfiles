package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

func jwt(exp int64) string {
	payload := base64.RawURLEncoding.EncodeToString(fmt.Appendf(nil, `{"exp": %d}`, exp))
	return "header." + payload + ".signature"
}

func newTestHelper(t *testing.T) *helper {
	state = t.TempDir()
	h, err := newHelper(&config{
		ServerPort: 14321, ProxyPort: 14322, CredentialPort: 14323,
		NoProxy:     []string{"127.0.0.1", "::1", "llmproxy.tristanmayo.com"},
		Credentials: map[string]credentialSpec{"TOKEN": {File: filepath.Join(state, "upstream-token")}},
		Services:    map[string]route{"executor": {Target: "http://executor.localhost:4788/mcp"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	return h
}

func TestLoadConfigSubstitutesEnvironmentAndRejectsUnsafeTargets(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	t.Setenv("EXECUTOR_MCP_URL", "http://executor.localhost:4788/mcp")
	os.WriteFile(path, []byte(`{"services": {"executor": {"target": "${EXECUTOR_MCP_URL}", "headers": {"Authorization": "Bearer {{ TOKEN }}"}}}}`), 0o600)
	cfg, err := loadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Services["executor"].Target != "http://executor.localhost:4788/mcp" || cfg.Services["executor"].Headers["Authorization"] != "Bearer {{ TOKEN }}" {
		t.Fatalf("unexpected config %+v", cfg.Services)
	}
	for _, content := range []string{
		`{"services": {"executor": {"target": "${UNSET_TEST_VARIABLE}"}}}`,
		`{"services": {"executor": {"target": "https://user:secret@example.com/mcp"}}}`,
		`{"services": {"executor": {"target": "file:///etc/passwd"}}}`,
	} {
		os.WriteFile(path, []byte(content), 0o600)
		if _, err := loadConfig(path); err == nil {
			t.Errorf("expected %s to be rejected", content)
		}
	}
}

func TestFileCredentialAndPrivateStateSurviveRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "token")
	for _, content := range []string{"saved-token", "replacement"} {
		if saved, err := privateFile(path, content); err != nil || saved != "saved-token" {
			t.Fatalf("privateFile returned %q, %v", saved, err)
		}
	}
	if info, _ := os.Stat(path); info.Mode().Perm() != 0o600 {
		t.Fatalf("unexpected mode %v", info.Mode())
	}
	result, err := credentialResponse(context.Background(), credentialSpec{File: path})
	if err != nil || result.AccessToken != "saved-token" {
		t.Fatalf("credentialResponse returned %+v, %v", result, err)
	}
}

func TestIdentityTokenUsesItsActualExpiry(t *testing.T) {
	token := jwt(time.Now().Unix() + 1800)
	result, err := credentialResponse(context.Background(), credentialSpec{Command: []string{"echo", token}})
	if err != nil || result.AccessToken != token || result.ExpiresIn < 1790 || result.ExpiresIn > 1800 {
		t.Fatalf("credentialResponse returned %+v, %v", result, err)
	}
}

func TestExpiredOrFailedGeneratorsCannotSupplyCredentials(t *testing.T) {
	for _, command := range [][]string{{"echo", jwt(1)}, {"false"}, {"echo", "not-a-jwt"}} {
		if _, err := credentialResponse(context.Background(), credentialSpec{Command: command}); err == nil {
			t.Errorf("expected %v to fail", command)
		}
	}
}

func postToken(t *testing.T, server *httptest.Server, key, token string) *http.Response {
	response, err := http.PostForm(server.URL+"/token", url.Values{"grant_type": {"refresh_token"}, "client_id": {key}, "refresh_token": {token}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { response.Body.Close() })
	return response
}

func TestCredentialEndpointRequiresItsCapabilityAndFixedKey(t *testing.T) {
	h := newTestHelper(t)
	server := httptest.NewServer(h.handler())
	defer server.Close()
	for _, request := range [][2]string{{"TOKEN", "wrong"}, {"ARBITRARY_COMMAND", h.refreshToken}} {
		if response := postToken(t, server, request[0], request[1]); response.StatusCode != http.StatusUnauthorized {
			t.Fatalf("%v returned HTTP %d", request, response.StatusCode)
		}
	}
	var result tokenResponse
	json.NewDecoder(postToken(t, server, "TOKEN", h.refreshToken).Body).Decode(&result)
	if result != (tokenResponse{AccessToken: "pending-initialization", ExpiresIn: 1}) {
		t.Fatalf("unexpected pending response %+v", result)
	}
	os.WriteFile(filepath.Join(state, "upstream-token"), []byte("real-file-token"), 0o600)
	h.ready.Store(true)
	response := postToken(t, server, "TOKEN", h.refreshToken)
	json.NewDecoder(response.Body).Decode(&result)
	if result.AccessToken != "real-file-token" || response.Header.Get("Cache-Control") != "no-store" {
		t.Fatalf("unexpected response %+v %v", result, response.Header)
	}
}

func TestHelperHasNoMCPForwardingEndpoint(t *testing.T) {
	server := httptest.NewServer(newTestHelper(t).handler())
	defer server.Close()
	for _, test := range []struct {
		path, header, value string
		status              int
	}{
		{"/token", "Origin", "https://example.com", http.StatusForbidden},
		{"/token", "Host", "attacker.example", http.StatusForbidden},
		{"/executor", "", "", http.StatusNotFound},
		{"/payload-production", "", "", http.StatusNotFound},
	} {
		request, _ := http.NewRequest("POST", server.URL+test.path, nil)
		if test.header == "Host" {
			request.Host = test.value
		} else if test.header != "" {
			request.Header.Set(test.header, test.value)
		}
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != test.status {
			t.Errorf("%s %s=%s returned HTTP %d", test.path, test.header, test.value, response.StatusCode)
		}
	}
}

func TestHealthOnlyReportsReadyAfterProvisioning(t *testing.T) {
	h := newTestHelper(t)
	server := httptest.NewServer(h.handler())
	defer server.Close()
	for _, want := range []int{http.StatusServiceUnavailable, http.StatusOK} {
		response, err := http.Get(server.URL + "/health")
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != want {
			t.Fatalf("health returned HTTP %d, want %d", response.StatusCode, want)
		}
		h.ready.Store(true)
	}
}

func TestNetworkProxyEnvironmentAndCAArePrivateAndExcludeModelProxy(t *testing.T) {
	h := newTestHelper(t)
	certificate := filepath.Join(state, "ca.pem")
	environment := clientEnvironment(h.config, "test-capability", certificate)
	if environment["HTTP_PROXY"] != "http://test-capability:dotfiles@127.0.0.1:14322" ||
		environment["HTTPS_PROXY"] != environment["HTTP_PROXY"] || environment["http_proxy"] != environment["HTTP_PROXY"] ||
		environment["no_proxy"] != environment["NO_PROXY"] || environment["CODEX_CA_CERTIFICATE"] != certificate {
		t.Fatalf("unexpected environment %v", environment)
	}
	noProxy := strings.Split(environment["NO_PROXY"], ",")
	if slices.Contains(noProxy, "localhost") || !slices.Contains(noProxy, "llmproxy.tristanmayo.com") {
		t.Fatalf("unexpected NO_PROXY %v", noProxy)
	}
	for _, name := range []string{"EXECUTOR_MCP_URL", "CODEX_EXECUTOR_CONFIG"} {
		if _, ok := environment[name]; ok {
			t.Fatalf("environment must not contain %s", name)
		}
	}
	if err := publishEnvironment(environment); err != nil {
		t.Fatal(err)
	}
	if info, _ := os.Stat(filepath.Join(state, "proxy.env")); info.Mode().Perm() != 0o600 {
		t.Fatalf("unexpected mode %v", info.Mode())
	}
	if _, err := os.Stat(filepath.Join(state, "proxy.env.tmp")); !os.IsNotExist(err) {
		t.Fatal("temporary environment file was left behind")
	}
}

type vaultCall struct {
	method, path string
	body         map[string]any
}

func TestBootstrapPreservesProxyTokenAndMergesServices(t *testing.T) {
	h := newTestHelper(t)
	h.config.Services["executor"] = route{Target: "http://executor.localhost:4788/mcp", Headers: map[string]string{"Authorization": "Bearer {{ TOKEN }}"}}
	h.config.Services["public-mcp"] = route{Target: "https://public.example/mcp"}
	os.WriteFile(filepath.Join(state, "proxy-token"), []byte("existing-client-token"), 0o600)
	os.WriteFile(filepath.Join(state, "managed-services.json"), []byte(`["executor", "removed-from-config"]`), 0o600)
	var mu sync.Mutex
	var calls []vaultCall
	vault := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		mu.Lock()
		calls = append(calls, vaultCall{r.Method, r.URL.Path, body})
		mu.Unlock()
		responses := map[string]string{
			"/v1/status":      `{"initialized": true}`,
			"/v1/auth/login":  `{"token": "owner-test-token"}`,
			"/v1/auth/me":     `{"agent_name": "coding-agents"}`,
			"/v1/mitm/ca.pem": "test-ca-certificate",
		}
		response, ok := responses[r.URL.Path]
		if !ok {
			response = "{}"
		}
		if r.URL.Path == "/v1/vaults" {
			w.WriteHeader(http.StatusCreated)
		}
		io.WriteString(w, response)
	}))
	defer vault.Close()
	h.address = vault.URL
	if err := h.bootstrap(context.Background()); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	var deleted []string
	var services []any
	for _, call := range calls {
		switch {
		case call.path == "/v1/agents" || strings.HasSuffix(call.path, "/rotate"):
			t.Fatalf("proxy token was replaced via %s", call.path)
		case call.path == "/v1/vaults/dotfiles/services" && call.method != "POST":
			t.Fatalf("services were replaced via %s", call.method)
		case call.path == "/v1/vaults/dotfiles/services":
			services = call.body["services"].([]any)
		case call.method == "DELETE":
			deleted = append(deleted, call.path)
		}
	}
	if !slices.Equal(deleted, []string{"/v1/vaults/dotfiles/services/removed-from-config"}) {
		t.Fatalf("unexpected deletions %v", deleted)
	}
	want := []map[string]any{
		{"name": "executor", "host": "executor.localhost:4788", "path": "/mcp*", "auth": map[string]any{"type": "custom", "headers": map[string]any{"Authorization": "Bearer {{ TOKEN }}"}}},
		{"name": "public-mcp", "host": "public.example", "path": "/mcp*", "auth": map[string]any{"type": "passthrough"}},
	}
	if got, _ := json.Marshal(services); string(got) != string(must(json.Marshal(want))) {
		t.Fatalf("unexpected services %s", got)
	}
	if managed, _ := os.ReadFile(filepath.Join(state, "managed-services.json")); string(managed) != `["executor","public-mcp"]` {
		t.Fatalf("unexpected managed services %s", managed)
	}
	if environment, _ := os.ReadFile(filepath.Join(state, "proxy.env")); !h.ready.Load() || !strings.Contains(string(environment), "existing-client-token") {
		t.Fatal("helper did not publish the existing proxy token")
	}
}

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}
