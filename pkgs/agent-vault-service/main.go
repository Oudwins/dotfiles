// agent-vault-service runs Agent Vault with a generated master password and
// provisions it unattended, serving configured credentials over Agent Vault's
// OAuth refresh protocol.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log"
	"maps"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
	"unicode"
)

const (
	vault = "dotfiles"
	owner = "tmx@agent-vault.local"
)

var state = func() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".agent-vault")
}()

type credentialSpec struct {
	File    string   `json:"file"`
	Command []string `json:"command"`
}

type route struct {
	Target  string            `json:"target"`
	Headers map[string]string `json:"headers"`
}

type config struct {
	ServerPort     int                       `json:"serverPort"`
	ProxyPort      int                       `json:"proxyPort"`
	CredentialPort int                       `json:"credentialPort"`
	NoProxy        []string                  `json:"noProxy"`
	Credentials    map[string]credentialSpec `json:"credentials"`
	Services       map[string]route          `json:"services"`
}

func loadConfig(path string) (*config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var missing []string
	expanded := os.Expand(string(data), func(name string) string {
		if name == "$" {
			return "$"
		}
		value, ok := os.LookupEnv(name)
		if !ok {
			missing = append(missing, name)
		}
		return value
	})
	if len(missing) > 0 {
		return nil, fmt.Errorf("config references unset variables: %s", strings.Join(missing, ", "))
	}
	var cfg config
	if err := json.Unmarshal([]byte(expanded), &cfg); err != nil {
		return nil, err
	}
	for _, entry := range cfg.Services {
		target, err := url.Parse(entry.Target)
		if err != nil || (target.Scheme != "http" && target.Scheme != "https") || target.Hostname() == "" || target.User != nil || target.Fragment != "" {
			return nil, errors.New("service targets must be HTTP URLs without credentials or fragments")
		}
	}
	return &cfg, nil
}

func privateFile(path, content string) (string, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", err
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if errors.Is(err, fs.ErrExist) {
		data, err := os.ReadFile(path)
		return strings.TrimSpace(string(data)), err
	}
	if err != nil {
		return "", err
	}
	if _, err := file.WriteString(content); err != nil {
		file.Close()
		return "", err
	}
	return content, file.Close()
}

func startServer(cfg *config) error {
	path := filepath.Join(state, "master-password")
	if _, err := privateFile(path, rand.Text()); err != nil {
		return err
	}
	password, err := os.Open(path)
	if err != nil {
		return err
	}
	defer password.Close()
	command := exec.Command("agent-vault", "server", "--password-stdin", "--host", "127.0.0.1",
		"--port", strconv.Itoa(cfg.ServerPort), "--mitm-port", strconv.Itoa(cfg.ProxyPort))
	command.Stdin, command.Stdout, command.Stderr = password, os.Stdout, os.Stderr
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	if err := command.Start(); err != nil {
		return err
	}
	var stopping atomic.Bool
	go func() {
		for received := range signals {
			stopping.Store(true)
			command.Process.Signal(received)
		}
	}()
	if err := command.Wait(); err != nil && !stopping.Load() {
		return err
	}
	return nil
}

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type,omitempty"`
	ExpiresIn   int    `json:"expires_in"`
}

func expandHome(path string) string {
	if rest, ok := strings.CutPrefix(path, "~/"); ok {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, rest)
	}
	return path
}

func jwtLifetime(token string) (int, error) {
	parts := strings.Split(token, ".")
	if len(parts) < 2 {
		return 0, errors.New("credential command did not print a JWT")
	}
	payload, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(parts[1], "="))
	if err != nil {
		return 0, err
	}
	var claims struct {
		Exp float64 `json:"exp"`
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return 0, err
	}
	return int(claims.Exp - float64(time.Now().Unix())), nil
}

func credentialResponse(ctx context.Context, spec credentialSpec) (tokenResponse, error) {
	var token string
	lifetime := 3600
	switch {
	case spec.File != "":
		data, err := os.ReadFile(expandHome(spec.File))
		if err != nil {
			return tokenResponse{}, err
		}
		token = strings.TrimSpace(string(data))
	case len(spec.Command) > 0:
		ctx, cancel := context.WithTimeout(ctx, 25*time.Second)
		defer cancel()
		command := exec.CommandContext(ctx, spec.Command[0], spec.Command[1:]...)
		command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		command.Cancel = func() error { return syscall.Kill(-command.Process.Pid, syscall.SIGKILL) }
		output, err := command.Output()
		if err != nil {
			return tokenResponse{}, errors.New("credential command failed; check gcloud authentication")
		}
		token = strings.TrimSpace(string(output))
		if lifetime, err = jwtLifetime(token); err != nil {
			return tokenResponse{}, err
		}
	default:
		return tokenResponse{}, errors.New("credential needs a file or command")
	}
	if token == "" || strings.ContainsFunc(token, unicode.IsSpace) || lifetime <= 300 {
		return tokenResponse{}, errors.New("credential is empty, invalid, or expires too soon")
	}
	return tokenResponse{AccessToken: token, TokenType: "Bearer", ExpiresIn: lifetime}, nil
}

func localRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if name, _, err := net.SplitHostPort(host); err == nil {
			host = name
		}
		if _, origin := r.Header["Origin"]; origin || (host != "127.0.0.1" && host != "localhost") {
			http.Error(w, "Forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func clientEnvironment(cfg *config, token, certificate string) map[string]string {
	proxy := (&url.URL{Scheme: "http", User: url.UserPassword(token, vault), Host: fmt.Sprintf("127.0.0.1:%d", cfg.ProxyPort)}).String()
	environment := map[string]string{
		"HTTP_PROXY": proxy, "HTTPS_PROXY": proxy,
		"NO_PROXY":           strings.Join(cfg.NoProxy, ","),
		"NODE_USE_ENV_PROXY": "1",
	}
	for _, name := range []string{"HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY"} {
		environment[strings.ToLower(name)] = environment[name]
	}
	for _, name := range []string{"SSL_CERT_FILE", "CODEX_CA_CERTIFICATE", "NODE_EXTRA_CA_CERTS", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "GIT_SSL_CAINFO", "DENO_CERT"} {
		environment[name] = certificate
	}
	return environment
}

var shellSafe = regexp.MustCompile(`^[\w@%+=:,./-]+$`)

func shellQuote(value string) string {
	if shellSafe.MatchString(value) {
		return value
	}
	return "'" + strings.ReplaceAll(value, "'", `'"'"'`) + "'"
}

func publishEnvironment(environment map[string]string) error {
	var content strings.Builder
	for _, name := range slices.Sorted(maps.Keys(environment)) {
		fmt.Fprintf(&content, "export %s=%s\n", name, shellQuote(environment[name]))
	}
	temporary := filepath.Join(state, "proxy.env.tmp")
	if err := os.WriteFile(temporary, []byte(content.String()), 0o600); err != nil {
		return err
	}
	if err := os.Chmod(temporary, 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, filepath.Join(state, "proxy.env"))
}

type serviceAuth struct {
	Type    string            `json:"type"`
	Headers map[string]string `json:"headers,omitempty"`
}

type serviceRule struct {
	Name string      `json:"name"`
	Host string      `json:"host"`
	Path string      `json:"path"`
	Auth serviceAuth `json:"auth"`
}

// Targets are validated by loadConfig.
func serviceRules(services map[string]route) []serviceRule {
	var rules []serviceRule
	for _, name := range slices.Sorted(maps.Keys(services)) {
		entry := services[name]
		target, _ := url.Parse(entry.Target)
		auth := serviceAuth{Type: "passthrough"}
		if len(entry.Headers) > 0 {
			auth = serviceAuth{Type: "custom", Headers: entry.Headers}
		}
		rules = append(rules, serviceRule{Name: name, Host: target.Host, Path: strings.TrimRight(target.Path, "/") + "*", Auth: auth})
	}
	return rules
}

type helper struct {
	config       *config
	address      string
	password     string
	refreshToken string
	client       *http.Client
	ready        atomic.Bool
}

func newHelper(cfg *config) (*helper, error) {
	password, err := privateFile(filepath.Join(state, "owner-password"), rand.Text())
	if err != nil {
		return nil, err
	}
	refreshToken, err := privateFile(filepath.Join(state, "credential-token"), rand.Text())
	if err != nil {
		return nil, err
	}
	return &helper{
		config:       cfg,
		address:      fmt.Sprintf("http://127.0.0.1:%d", cfg.ServerPort),
		password:     password,
		refreshToken: refreshToken,
		client: &http.Client{
			Timeout:   30 * time.Second,
			Transport: &http.Transport{DialContext: (&net.Dialer{Timeout: 10 * time.Second}).DialContext},
		},
	}, nil
}

func (h *helper) api(ctx context.Context, method, path, token string, payload, result any, allowed ...int) error {
	if len(allowed) == 0 {
		allowed = []int{http.StatusOK, http.StatusCreated}
	}
	var body io.Reader
	if payload != nil {
		data, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		body = bytes.NewReader(data)
	}
	request, err := http.NewRequestWithContext(ctx, method, h.address+path, body)
	if err != nil {
		return err
	}
	if payload != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response, err := h.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if !slices.Contains(allowed, response.StatusCode) {
		return fmt.Errorf("Agent Vault %s %s returned HTTP %d", method, path, response.StatusCode)
	}
	if result == nil {
		return nil
	}
	return json.NewDecoder(response.Body).Decode(result)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(value)
}

func (h *helper) token(w http.ResponseWriter, r *http.Request) {
	key := r.PostFormValue("client_id")
	spec, known := h.config.Credentials[key]
	if r.PostFormValue("grant_type") != "refresh_token" || !known ||
		subtle.ConstantTimeCompare([]byte(r.PostFormValue("refresh_token")), []byte(h.refreshToken)) != 1 {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	// Provision refresh metadata without requiring gcloud or SOPS at startup.
	// The one-second expiry forces a real refresh before the first request.
	if !h.ready.Load() {
		writeJSON(w, http.StatusOK, tokenResponse{AccessToken: "pending-initialization", ExpiresIn: 1})
		return
	}
	result, err := credentialResponse(r.Context(), spec)
	if err != nil {
		log.Printf("ERROR Credential generation failed for %s: %v", key, err)
		http.Error(w, "Credential generation failed; check service logs and gcloud authentication", http.StatusBadGateway)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, result)
}

func (h *helper) health(w http.ResponseWriter, r *http.Request) {
	status := http.StatusServiceUnavailable
	if h.ready.Load() {
		status = http.StatusOK
	}
	writeJSON(w, status, map[string]bool{"ready": h.ready.Load()})
}

func (h *helper) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /token", h.token)
	mux.HandleFunc("GET /health", h.health)
	return localRequest(mux)
}

func (h *helper) bootstrap(ctx context.Context) error {
	var status struct {
		Initialized bool `json:"initialized"`
	}
	deadline := time.Now().Add(time.Minute)
	for h.api(ctx, "GET", "/v1/status", "", nil, &status) != nil {
		if time.Now().After(deadline) {
			return errors.New("Agent Vault did not become ready")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
	authPath := "/v1/auth/register"
	if status.Initialized {
		authPath = "/v1/auth/login"
	}
	var login struct {
		Token string `json:"token"`
	}
	credentials := map[string]string{"email": owner, "password": h.password, "device_label": "dotfiles-service"}
	if err := h.api(ctx, "POST", authPath, "", credentials, &login); err != nil {
		return err
	}
	ownerToken := login.Token
	if err := h.api(ctx, "PUT", "/v1/admin/settings", ownerToken, map[string]bool{"invite_only": true}, nil); err != nil {
		return err
	}
	if err := h.api(ctx, "POST", "/v1/vaults", ownerToken, map[string]string{"name": vault}, nil, http.StatusCreated, http.StatusConflict); err != nil {
		return err
	}
	if err := h.api(ctx, "PATCH", "/v1/vaults/"+vault+"/settings", ownerToken, map[string]string{"unmatched_host_policy": "passthrough"}, nil); err != nil {
		return err
	}
	for _, key := range slices.Sorted(maps.Keys(h.config.Credentials)) {
		if err := h.api(ctx, "POST", "/v1/credentials/oauth/tokens", ownerToken, map[string]string{
			"vault": vault, "key": key, "client_id": key,
			"token_url":     fmt.Sprintf("http://127.0.0.1:%d/token", h.config.CredentialPort),
			"refresh_token": h.refreshToken,
		}, nil); err != nil {
			return err
		}
	}
	// Upsert by name so services added through the UI survive restarts; only
	// services this helper created earlier are removed when dropped from config.
	services := serviceRules(h.config.Services)
	if len(services) > 0 {
		if err := h.api(ctx, "POST", "/v1/vaults/"+vault+"/services", ownerToken, map[string]any{"services": services}, nil); err != nil {
			return err
		}
	}
	managedPath := filepath.Join(state, "managed-services.json")
	var managed []string
	data, err := os.ReadFile(managedPath)
	if err == nil {
		err = json.Unmarshal(data, &managed)
	}
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	for _, name := range managed {
		if _, ok := h.config.Services[name]; !ok {
			if err := h.api(ctx, "DELETE", "/v1/vaults/"+vault+"/services/"+url.PathEscape(name), ownerToken, nil, nil, http.StatusOK, http.StatusNotFound); err != nil {
				return err
			}
		}
	}
	data, _ = json.Marshal(slices.Sorted(maps.Keys(h.config.Services)))
	if err := os.WriteFile(managedPath, data, 0o600); err != nil {
		return err
	}
	tokenPath := filepath.Join(state, "proxy-token")
	var token string
	if data, err := os.ReadFile(tokenPath); err == nil {
		token = strings.TrimSpace(string(data))
	}
	if token != "" {
		var identity struct {
			AgentName string `json:"agent_name"`
		}
		if err := h.api(ctx, "GET", "/v1/auth/me", token, nil, &identity, http.StatusOK, http.StatusUnauthorized); err != nil {
			return err
		}
		if identity.AgentName != "coding-agents" {
			token = ""
		}
	}
	if token == "" {
		var agent struct {
			Token string `json:"av_agent_token"`
		}
		if err := h.api(ctx, "POST", "/v1/agents", ownerToken, map[string]any{
			"name": "coding-agents", "vaults": []map[string]string{{"vault_name": vault, "vault_role": "proxy"}},
		}, &agent, http.StatusCreated, http.StatusConflict); err != nil {
			return err
		}
		if agent.Token == "" {
			if err := h.api(ctx, "POST", "/v1/agents/coding-agents/rotate", ownerToken, map[string]any{}, &agent); err != nil {
				return err
			}
		}
		token = agent.Token
		if err := os.WriteFile(tokenPath, []byte(token), 0o600); err != nil {
			return err
		}
	}
	request, err := http.NewRequestWithContext(ctx, "GET", h.address+"/v1/mitm/ca.pem", nil)
	if err != nil {
		return err
	}
	response, err := h.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("Agent Vault CA certificate returned HTTP %d", response.StatusCode)
	}
	certificate, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}
	certificatePath := filepath.Join(state, "ca.pem")
	if err := os.WriteFile(certificatePath, certificate, 0o600); err != nil {
		return err
	}
	if err := publishEnvironment(clientEnvironment(h.config, token, certificatePath)); err != nil {
		return err
	}
	h.ready.Store(true)
	log.Printf("INFO Agent Vault configured for direct network proxy use with %d services", len(services))
	return nil
}

func (h *helper) run(ctx context.Context) error {
	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", h.config.CredentialPort))
	if err != nil {
		return err
	}
	server := &http.Server{Handler: h.handler(), ReadHeaderTimeout: 10 * time.Second}
	go server.Serve(listener)
	defer server.Close()
	if err := h.bootstrap(ctx); err != nil && ctx.Err() == nil {
		return err
	}
	<-ctx.Done()
	return nil
}

func run(args []string) error {
	if len(args) < 1 || (args[0] != "server" && args[0] != "credentials") {
		return errors.New("usage: agent-vault-service {server|credentials} [--config path]")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	flags := flag.NewFlagSet(args[0], flag.ExitOnError)
	configPath := flags.String("config", filepath.Join(home, ".config/agent-vault/config.json"), "configuration file")
	flags.Parse(args[1:])
	syscall.Umask(0o077)
	cfg, err := loadConfig(*configPath)
	if err != nil {
		return err
	}
	if args[0] == "server" {
		return startServer(cfg)
	}
	h, err := newHelper(cfg)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	return h.run(ctx)
}

func main() {
	log.SetFlags(0)
	if err := run(os.Args[1:]); err != nil {
		log.Printf("ERROR %v", err)
		os.Exit(1)
	}
}
