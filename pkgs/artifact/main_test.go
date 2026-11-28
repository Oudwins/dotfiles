package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"io"
	"maps"
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

// The GET Object example from AWS's Signature Version 4 documentation for S3.
func TestSignMatchesAWSExample(t *testing.T) {
	request, _ := http.NewRequest(http.MethodGet, "https://examplebucket.s3.amazonaws.com/test.txt", nil)
	request.Header.Set("Range", "bytes=0-9")
	request.Header.Set("X-Amz-Content-Sha256", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	sign(request, "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", "us-east-1",
		time.Date(2013, 5, 24, 0, 0, 0, 0, time.UTC))
	want := "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, " +
		"SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, " +
		"Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
	if got := request.Header.Get("Authorization"); got != want {
		t.Fatalf("Authorization:\n got %s\nwant %s", got, want)
	}
}

func TestValidKey(t *testing.T) {
	for key, want := range map[string]bool{
		"report-1a2b3c4d/index.html":   true,
		"report-1a2b3c4d/a b/c.css":    true,
		"":                             false,
		"notes/index.html":             false,
		"report-1a2b3c4d":              false,
		"report-1a2b3c4d/":             false,
		"/report-1a2b3c4d/index.html":  false,
		"report-1a2b3c4d//index.html":  false,
		"report-1a2b3c4d/../secret":    false,
		"report-1a2b3c4d/./index.html": false,
		"report-1a2b3c4d/a\\b":         false,
		"report-1a2b3c4d/a\nb":         false,
	} {
		if got := validKey(key); got != want {
			t.Errorf("validKey(%q) = %v, want %v", key, got, want)
		}
	}
}

func TestEscapePath(t *testing.T) {
	if got, want := escapePath("a b/c+d!.html"), "a%20b/c%2Bd%21.html"; got != want {
		t.Fatalf("escapePath = %q, want %q", got, want)
	}
}

func TestNewID(t *testing.T) {
	id := newID("/tmp/Q3 Report (final).html")
	if !strings.HasPrefix(id, "q3-report-final-") || !validID.MatchString(id) {
		t.Fatalf("newID = %q", id)
	}
	if id := newID("/tmp/.html"); !strings.HasPrefix(id, "artifact-") {
		t.Fatalf("newID for an empty name = %q", id)
	}
	if id := newID(strings.Repeat("long name ", 10)); !validID.MatchString(id) {
		t.Fatalf("newID for a long name = %q", id)
	}
}

// captureStderr runs f and returns what it printed to stderr.
func captureStderr(t *testing.T, f func()) string {
	t.Helper()
	read, write, _ := os.Pipe()
	saved := os.Stderr
	os.Stderr = write
	f()
	os.Stderr = saved
	write.Close()
	out, _ := io.ReadAll(read)
	return string(out)
}

// captureStdout runs f and returns what it printed to stdout.
func captureStdout(t *testing.T, f func() error) (string, error) {
	t.Helper()
	read, write, _ := os.Pipe()
	saved := os.Stdout
	os.Stdout = write
	err := f()
	os.Stdout = saved
	write.Close()
	out, _ := io.ReadAll(read)
	return string(out), err
}

func writeFiles(t *testing.T, root string, files map[string]string) {
	t.Helper()
	for name, content := range files {
		file := filepath.Join(root, filepath.FromSlash(name))
		os.MkdirAll(filepath.Dir(file), 0o755)
		if err := os.WriteFile(file, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// fakeClaude stands in for claude.ai's Artifacts API, OAuth token endpoint and
// content host, recording requests.
type fakeClaude struct {
	t        *testing.T
	mu       sync.Mutex
	requests []string
	deploys  []map[string]any
	perm     map[string]any
	patches  []map[string]any
	refresh  int
	// accepted is the access token the API takes; others answer 401.
	accepted string
	threads  []any
	version  string
	files    map[string]string
	server   *httptest.Server
}

const fakeSlug = "0b5c9d3e-1a2b-4c3d-8e9f-0123456789ab"

func newFakeClaude(t *testing.T) *fakeClaude {
	f := &fakeClaude{t: t, accepted: "access-1", version: "v1",
		perm:  map[string]any{"read": map[string]any{"mode": "owner"}, "version": "p1", "assignableReadModes": []string{"owner", "users", "org"}},
		files: map[string]string{"index.html": "<h1>hi</h1>", "sub/a.css": "body{}"}}
	f.server = httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(f.server.Close)
	saved := []string{claudeAPI, claudeTokenURL, claudeContentHost}
	claudeAPI, claudeTokenURL, claudeContentHost = f.server.URL, f.server.URL+"/oauth/token", f.server.URL+"/content/%s"
	t.Cleanup(func() { claudeAPI, claudeTokenURL, claudeContentHost = saved[0], saved[1], saved[2] })
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("ARTIFACT_BACKEND", "claude")
	return f
}

func (f *fakeClaude) login(expiresAt int64) {
	file, _ := claudeCredentialsFile()
	if err := writeClaudeCredentials(file, &claudeCredentials{AccessToken: "access-1", RefreshToken: "refresh-1", ExpiresAt: expiresAt}); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fakeClaude) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.requests = append(f.requests, r.Method+" "+r.URL.Path)
	reply := func(value any) { json.NewEncoder(w).Encode(value) }
	var body map[string]any
	json.NewDecoder(r.Body).Decode(&body)
	if r.URL.Path == "/unavailable" {
		http.Error(w, "down", http.StatusServiceUnavailable)
		return
	}
	if r.URL.Path == "/oauth/token" {
		f.refresh++
		if body["refresh_token"] != "refresh-1" || body["client_id"] != claudeClientID {
			http.Error(w, `{"error":"invalid_grant"}`, http.StatusBadRequest)
			return
		}
		reply(map[string]any{"access_token": f.accepted, "refresh_token": "refresh-2", "expires_in": 3600})
		return
	}
	if strings.HasPrefix(r.URL.Path, "/content/") {
		if r.Header.Get("Authorization") != "" || r.URL.Query().Get("__frame_t") != "asset-token" {
			http.Error(w, "bad token", http.StatusForbidden)
			return
		}
		key := strings.TrimPrefix(r.URL.Path, "/content/"+fakeSlug+"/_f/"+f.version+"/_src/")
		content, ok := f.files[key]
		if !ok {
			http.NotFound(w, r)
			return
		}
		io.WriteString(w, content)
		return
	}
	if r.Header.Get("Authorization") != "Bearer "+f.accepted || r.Header.Get("anthropic-beta") != "oauth-2025-04-20" {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	switch {
	case r.URL.Path == "/api/frame/deploy/direct":
		f.deploys = append(f.deploys, body)
		reply(map[string]any{"slug": fakeSlug, "version": "v2"})
	case r.URL.Path == "/api/frame/perm/"+fakeSlug && r.Method == http.MethodGet:
		reply(f.perm)
	case r.URL.Path == "/api/frame/perm/"+fakeSlug && r.Method == http.MethodPatch:
		if r.Header.Get("If-Match") != f.perm["version"] {
			http.Error(w, "stale", http.StatusPreconditionFailed)
			return
		}
		f.patches = append(f.patches, body)
		f.perm = map[string]any{"read": body["read"], "version": "p2"}
	case r.URL.Path == "/api/frame/"+fakeSlug:
		var files []any
		for path, content := range f.files {
			sum := sha256.Sum256([]byte(content))
			files = append(files, map[string]any{"path": path, "sha256": hex.EncodeToString(sum[:])})
		}
		reply(map[string]any{"ver": f.version, "assetToken": "asset-token", "files": files})
	case r.URL.Path == "/api/frame/artifacts":
		rel, token := r.URL.Query().Get("rel"), r.URL.Query().Get("page_token")
		switch {
		case rel == "mine" && token == "":
			reply(map[string]any{"artifacts": []any{map[string]any{"id": "a1", "title": "One", "updated_at": "2026-11-02"}}, "next_page_token": "t2"})
		case rel == "mine":
			reply(map[string]any{"artifacts": []any{map[string]any{"id": "a2", "title": "Two", "created_at": "2026-11-01"}}})
		default:
			reply(map[string]any{"artifacts": []any{map[string]any{"id": "a3", "title": "Theirs", "updated_at": "2026-11-03"}, map[string]any{"id": "a1"}}})
		}
	case r.URL.Path == "/api/frame/comments/"+fakeSlug:
		reply(map[string]any{"threads": f.threads, "names": map[string]string{"u1": "Ada"}})
	default:
		http.NotFound(w, r)
	}
}

func TestClaudeSlug(t *testing.T) {
	for input, want := range map[string]string{
		fakeSlug: fakeSlug,
		"https://claude.ai/code/artifact/" + fakeSlug: fakeSlug,
		"https://claude.ai/artifact/1111111111111111": "00000000-0000-0000-0000-000000000000",
		"https://claude.ai/artifact/111111111111111z": "00000000-0000-0000-0000-000000000039",
	} {
		if got, err := claudeSlug(input); err != nil || got != want {
			t.Errorf("claudeSlug(%q) = %q, %v; want %q", input, got, err, want)
		}
	}
	if _, err := claudeSlug("report-1a2b3c4d"); err == nil {
		t.Error("claudeSlug accepted an s3 ID")
	}
}

func TestClaudeNotLoggedIn(t *testing.T) {
	newFakeClaude(t)
	_, err := captureStdout(t, func() error { return list(nil) })
	if !errors.Is(err, errLogin) || err.Error() != "Could not upload. Please log in to Claude using: artifact -claude-login" {
		t.Fatalf("list without a login: %v", err)
	}
}

func TestClaudeRefresh(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(-time.Hour).UnixMilli())
	f.accepted = "access-2"
	if _, err := claudeList(); err != nil {
		t.Fatal(err)
	}
	file, _ := claudeCredentialsFile()
	info, err := os.Stat(file)
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("credentials file: %v %v", info.Mode(), err)
	}
	creds, _ := readClaudeCredentials(file)
	if creds.AccessToken != "access-2" || creds.RefreshToken != "refresh-2" || f.refresh != 1 {
		t.Fatalf("after refresh: %+v, %d refreshes", creds, f.refresh)
	}

	// A token the server rejects is refreshed once.
	f.login(time.Now().Add(time.Hour).UnixMilli())
	f.accepted = "access-3"
	if _, err := claudeList(); err != nil || f.refresh != 2 {
		t.Fatalf("after a 401: %v, %d refreshes", err, f.refresh)
	}

	// An outage at the token endpoint is not a lost login.
	saved := claudeTokenURL
	claudeTokenURL = f.server.URL + "/unavailable"
	writeClaudeCredentials(file, &claudeCredentials{AccessToken: "old", RefreshToken: "refresh-1", ExpiresAt: 1})
	if _, err := claudeList(); err == nil || errors.Is(err, errLogin) {
		t.Fatalf("token endpoint outage: %v", err)
	}
	claudeTokenURL = saved

	// A refused refresh means logging in again.
	writeClaudeCredentials(file, &claudeCredentials{AccessToken: "old", RefreshToken: "revoked", ExpiresAt: 1})
	if _, err := claudeList(); !errors.Is(err, errLogin) {
		t.Fatalf("refused refresh: %v", err)
	}
}

func TestClaudeNetworkErrorIsReported(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	claudeAPI = "http://127.0.0.1:1"
	_, err := claudeList()
	if err == nil || errors.Is(err, errLogin) || !strings.Contains(err.Error(), "network error") {
		t.Fatalf("network failure: %v", err)
	}
}

func TestClaudePublishSharesWithOrg(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	root := t.TempDir()
	writeFiles(t, root, map[string]string{
		"index.html": "<title>My Report</title>", "sub/app.js": "1", "logo.png": "\x89PNG",
		".env": "secret", ".git/config": "secret",
	})
	out, err := captureStdout(t, func() error { return publish([]string{root}) })
	if err != nil || out != "https://claude.ai/code/artifact/"+fakeSlug+"\n" {
		t.Fatalf("publish: %q, %v", out, err)
	}
	deploy := f.deploys[0]
	manifest := deploy["manifest"].(map[string]any)
	if got := slices.Sorted(maps.Keys(manifest)); !slices.Equal(got, []string{"index.html", "logo.png", "sub/app.js"}) {
		t.Fatalf("manifest paths: %v", got)
	}
	if png := manifest["logo.png"].(map[string]any); png["content"] != base64.StdEncoding.EncodeToString([]byte("\x89PNG")) || png["contentType"] != "image/png" {
		t.Fatalf("binary file: %v", png)
	}
	if deploy["title"] != "My Report" || deploy["mode"] != "replace" || deploy["slug"] != nil {
		t.Fatalf("deploy body: %v", deploy)
	}
	if len(f.patches) != 1 || f.patches[0]["read"].(map[string]any)["mode"] != "org" {
		t.Fatalf("share: %v", f.patches)
	}

	// -id updates in place on top of the live version; already shared, so no PATCH.
	out, err = captureStdout(t, func() error { return publish([]string{"-id", "https://claude.ai/code/artifact/" + fakeSlug, root}) })
	if err != nil || !strings.Contains(out, fakeSlug) {
		t.Fatalf("publish -id: %q, %v", out, err)
	}
	if deploy := f.deploys[1]; deploy["slug"] != fakeSlug || deploy["baseVersion"] != "v1" || len(f.patches) != 1 {
		t.Fatalf("update: %v, %d patches", deploy, len(f.patches))
	}
}

func TestClaudePublishShareFailure(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	root := filepath.Join(t.TempDir(), "report-$USER")
	writeFiles(t, root, map[string]string{"index.html": "x"})
	for _, perm := range []map[string]any{
		{"read": map[string]any{"mode": "owner"}, "version": "p1", "assignableReadModes": []string{"owner", "users"}},
		{"read": map[string]any{"mode": "org"}, "orgReadLevel": "view", "version": "p1"},
	} {
		f.perm = perm
		var out string
		var err error
		stderr := captureStderr(t, func() { out, err = captureStdout(t, func() error { return publish([]string{root}) }) })
		link := "https://claude.ai/code/artifact/" + fakeSlug
		if err == nil || out != link+"\n" || !strings.Contains(stderr, "isn't shared") || !strings.Contains(stderr, "publish -id "+link+" '"+root+"'") {
			t.Fatalf("share failure for %v: %q, %q, %v", perm, out, stderr, err)
		}
	}
}

func TestClaudePublishLimits(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	for files, want := range map[string]map[string]string{
		"top-level index.html":             {"sub/index.html": "x"},
		`don't serve files of type ".exe"`: {"index.html": "x", "tool.exe": "x"},
		"only as UTF-8":                    {"index.html": "\xff\xfe"},
	} {
		root := t.TempDir()
		writeFiles(t, root, want)
		_, err := captureStdout(t, func() error { return publish([]string{root}) })
		if err == nil || !strings.Contains(err.Error(), files) {
			t.Errorf("publish %v: %v, want %q", want, err, files)
		}
	}
	if len(f.deploys) != 0 {
		t.Fatal("published despite a limit")
	}
}

func TestClaudePull(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	dest := filepath.Join(t.TempDir(), "out")
	if _, err := captureStdout(t, func() error { return pull([]string{fakeSlug, dest}) }); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(dest, "sub", "a.css")); string(data) != "body{}" {
		t.Fatalf("pulled sub/a.css: %q", data)
	}
	if err := pullFiles(dest, []string{"x"}, nil); err == nil || !strings.Contains(err.Error(), "not empty") {
		t.Fatalf("pull into a non-empty directory: %v", err)
	}
	// A failed download writes nothing, so the pull can be retried.
	failed := filepath.Join(t.TempDir(), "failed")
	if err := pullFiles(failed, []string{"index.html", "missing.css"}, func(key string) ([]byte, error) {
		if key == "missing.css" {
			return nil, errors.New("gone")
		}
		return []byte("x"), nil
	}); err == nil {
		t.Fatal("pull with a failed download succeeded")
	}
	if entries, _ := os.ReadDir(failed); len(entries) != 0 {
		t.Fatalf("a failed pull left %v", entries)
	}
	f.files = map[string]string{"../escape": "x"}
	if _, err := captureStdout(t, func() error { return pull([]string{fakeSlug, t.TempDir()}) }); err == nil || !strings.Contains(err.Error(), "unsafe") {
		t.Fatalf("pull with an unsafe path: %v", err)
	}
}

func TestClaudeList(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	out, err := captureStdout(t, func() error { return list([]string{"--json"}) })
	if err != nil {
		t.Fatal(err)
	}
	var rows []listedArtifact
	json.Unmarshal([]byte(out), &rows)
	var got []string
	for _, row := range rows {
		got = append(got, row.ID+" "+row.Owner+" "+row.Updated)
	}
	want := []string{"a1 me 2026-11-02", "a2 me 2026-11-01", "a3 shared with me 2026-11-03"}
	if !slices.Equal(got, want) {
		t.Fatalf("list: %q", got)
	}
}

func fakeThread(id, resolvedAt string, comments ...map[string]any) map[string]any {
	return map[string]any{"id": id, "resolved_at": resolvedAt, "anchor": map[string]any{"label": "the chart"}, "comments": comments}
}

func TestClaudeCommentsList(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	f.threads = []any{
		fakeThread("t1", "", map[string]any{"id": "c1", "author": map[string]any{"account": "u1"}, "text": "fix this", "created_at": "2026-11-01T10:00:00Z", "to_claude_at": "2026-11-01T10:00:00Z"}),
		fakeThread("t2", "2026-11-02T00:00:00Z", map[string]any{"id": "c2", "author": map[string]any{"role": "assistant"}, "text": "done"}),
	}
	out, err := captureStdout(t, func() error { return comments([]string{"list", fakeSlug, "--json"}) })
	if err != nil {
		t.Fatal(err)
	}
	var threads []thread
	json.Unmarshal([]byte(out), &threads)
	if len(threads) != 1 || threads[0].ID != "t1" || threads[0].AttachedTo != "the chart" {
		t.Fatalf("open threads: %+v", threads)
	}
	if c := threads[0].Comments[0]; c.Author != "Ada" || c.Text != "fix this" || !c.ToClaude || c.CreatedAt == "" {
		t.Fatalf("comment: %+v", c)
	}
	out, _ = captureStdout(t, func() error { return comments([]string{"list", "-all", fakeSlug}) })
	if !strings.Contains(out, "thread t2  resolved") || !strings.Contains(out, "Claude: done") || !strings.Contains(out, "on the chart") {
		t.Fatalf("all threads:\n%s", out)
	}
}

func TestClaudeWatch(t *testing.T) {
	f := newFakeClaude(t)
	f.login(time.Now().Add(time.Hour).UnixMilli())
	f.threads = []any{fakeThread("t1", "", map[string]any{"id": "old", "author": map[string]any{"account": "u1"}, "text": "before"})}
	go func() {
		time.Sleep(30 * time.Millisecond)
		f.mu.Lock()
		f.version = "v2"
		f.threads = []any{fakeThread("t1", "2026-11-03T00:00:00Z",
			map[string]any{"id": "old", "author": map[string]any{"account": "u1"}, "text": "before"},
			map[string]any{"id": "new", "author": map[string]any{"account": "u1"}, "text": "after", "to_claude_at": "x"})}
		f.mu.Unlock()
	}()
	out, err := captureStdout(t, func() error {
		return claudeWatch(t.Context(), fakeSlug, 10*time.Millisecond, 3, true, true)
	})
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(out), "\n")
	want := []string{
		`{"event":"version","version":"v2","previous":"v1"}`,
		`{"event":"comment","thread":"t1","comment":"new","author":"Ada","text":"after","to_claude":true,"attached_to":"the chart"}`,
		`{"event":"resolved","thread":"t1","at":"2026-11-03T00:00:00Z"}`,
	}
	if !slices.Equal(lines, want) {
		t.Fatalf("watch events:\n%s", out)
	}

	// -no-comments reads no comments; -count counts events, not polls.
	f.mu.Lock()
	f.requests = nil
	f.mu.Unlock()
	go func() {
		time.Sleep(30 * time.Millisecond)
		f.mu.Lock()
		f.version = "v3"
		f.mu.Unlock()
	}()
	out, _ = captureStdout(t, func() error { return claudeWatch(t.Context(), fakeSlug, 10*time.Millisecond, 1, false, false) })
	if out != "version v3 (was v2)\n" || slices.ContainsFunc(f.requests, func(r string) bool { return strings.Contains(r, "comments") }) {
		t.Fatalf("version-only watch: %q, %v", out, f.requests)
	}
}

func TestS3RefusesClaudeOnlyCommands(t *testing.T) {
	t.Setenv("ARTIFACT_BACKEND", "s3")
	for _, err := range []error{comments([]string{"list", "report-1a2b3c4d"}), watch([]string{"report-1a2b3c4d"})} {
		if err == nil || !strings.Contains(err.Error(), "not supported") {
			t.Errorf("s3: %v", err)
		}
	}
	t.Setenv("ARTIFACT_BACKEND", "ftp")
	if err := list(nil); err == nil || !strings.Contains(err.Error(), "s3 or claude") {
		t.Errorf("unknown backend: %v", err)
	}
}

func TestS3ID(t *testing.T) {
	for input, want := range map[string]string{
		"report-1a2b3c4d": "report-1a2b3c4d",
		"https://artifacts.r.test/report-1a2b3c4d/":           "report-1a2b3c4d",
		"https://artifacts.r.test/report-1a2b3c4d/sub/a.html": "report-1a2b3c4d",
	} {
		if got, err := s3ID(input); err != nil || got != want {
			t.Errorf("s3ID(%q) = %q, %v", input, got, err)
		}
	}
	t.Setenv("ARTIFACT_PUBLIC_URL", "http://127.0.0.1:9000/artifacts/")
	if got, err := s3ID("http://127.0.0.1:9000/artifacts/report-1a2b3c4d/"); err != nil || got != "report-1a2b3c4d" {
		t.Errorf("s3ID under a public URL with a path = %q, %v", got, err)
	}
	if _, err := s3ID("notes"); err == nil {
		t.Error("s3ID accepted an invented ID")
	}
}

// The upload server lists the bucket with its key, behind the bearer token,
// and the CLI lists and pulls through it.
func TestS3ListAndPull(t *testing.T) {
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.Header.Get("Authorization"), "AWS4-HMAC-SHA256 Credential=key/") || r.URL.Path != "/artifacts" {
			http.Error(w, "denied", http.StatusForbidden)
			return
		}
		if r.URL.Query().Get("continuation-token") == "" {
			io.WriteString(w, `<ListBucketResult><IsTruncated>true</IsTruncated><NextContinuationToken>a b+c</NextContinuationToken>
				<Contents><Key>site-1a2b3c4d/index.html</Key><Size>5</Size><LastModified>2026-11-01T00:00:00.000Z</LastModified></Contents>
				<Contents><Key>x.txt</Key><Size>1</Size><LastModified>2026-11-09T00:00:00.000Z</LastModified></Contents></ListBucketResult>`)
			return
		}
		if r.URL.RawQuery != "continuation-token=a%20b%2Bc&list-type=2" {
			http.Error(w, "query "+r.URL.RawQuery, http.StatusBadRequest)
			return
		}
		io.WriteString(w, `<ListBucketResult><IsTruncated>false</IsTruncated>
			<Contents><Key>site-1a2b3c4d/sub/a b.css</Key><Size>6</Size><LastModified>2026-11-02T00:00:00.000Z</LastModified></Contents>
			<Contents><Key>notes-0000aaaa/notes.html</Key><Size>3</Size><LastModified>2026-11-03T00:00:00.000Z</LastModified></Contents></ListBucketResult>`)
	}))
	defer storage.Close()
	endpoint, _ := url.Parse(storage.URL)
	upload := httptest.NewServer(&server{endpoint: endpoint, bucket: "artifacts", region: "us-east-1", accessKey: "key", secretKey: "secret", token: "tok", client: http.DefaultClient})
	defer upload.Close()

	response, _ := http.Get(upload.URL + "/")
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("listing without the token: %s", response.Status)
	}
	// Stands in for Agent Vault's router, adding the token.
	router := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		request, _ := http.NewRequest(r.Method, upload.URL+r.URL.Path, r.Body)
		request.Header.Set("Authorization", "Bearer tok")
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		w.WriteHeader(response.StatusCode)
		io.Copy(w, response.Body)
	}))
	defer router.Close()
	public := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "content of "+r.URL.Path)
	}))
	defer public.Close()
	t.Setenv("ARTIFACT_BACKEND", "s3")
	t.Setenv("ARTIFACT_UPLOAD_URL", router.URL)
	t.Setenv("ARTIFACT_PUBLIC_URL", public.URL)

	out, err := captureStdout(t, func() error { return list([]string{"-json"}) })
	if err != nil {
		t.Fatal(err)
	}
	var rows []listedArtifact
	json.Unmarshal([]byte(out), &rows)
	if len(rows) != 2 || rows[0].ID != "notes-0000aaaa" || rows[1].ID != "site-1a2b3c4d" || len(rows[1].Files) != 2 ||
		rows[1].Updated != "2026-11-02T00:00:00.000Z" || rows[1].URL != public.URL+"/site-1a2b3c4d/" {
		t.Fatalf("list: %s", out)
	}

	dest := filepath.Join(t.TempDir(), "site")
	if _, err := captureStdout(t, func() error { return pull([]string{public.URL + "/site-1a2b3c4d/", dest}) }); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(dest, "sub", "a b.css")); string(data) != "content of /site-1a2b3c4d/sub/a b.css" {
		t.Fatalf("pulled: %q", data)
	}
}

func TestParseArgsInterspersed(t *testing.T) {
	flags := flag.NewFlagSet("watch", flag.ExitOnError)
	interval := flags.Float64("interval", 30, "")
	asJSON := flags.Bool("json", false, "")
	got := parseArgs(flags, []string{"ID", "--interval", "5", "--json"}, 1)
	if got[0] != "ID" || *interval != 5 || !*asJSON {
		t.Fatalf("parseArgs: %v %v %v", got, *interval, *asJSON)
	}
}
