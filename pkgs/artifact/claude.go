// The Claude Artifacts backend: claude.ai's private, undocumented Artifacts
// ("frame") API, used with this CLI's own claude.ai OAuth login.
//
// Ported from, and only as much as these commands need:
//   - API calls: github.com/nikships/claude-artifact-cli
//     src/claude_artifact_cli/{api,commands}.py at ca2ad5fb44ac004bdcb38111e13f36dbccb285e5
//   - OAuth login and refresh: github.com/kamilio/claude-artifacts
//     src/auth.js at a8052979d58b9e99c0ea852036365df54c095fcf
//   - Org sharing and comment access: the Claude Code 2.1.323 bundle, where an
//     org-shared artifact's members can comment unless orgReadLevel is "view".
//
// Everything Claude-specific stays in this file.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"maps"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
)

// Endpoints; tests point them at a local server.
var (
	claudeAPI         = "https://api.anthropic.com"
	claudeTokenURL    = "https://platform.claude.com/v1/oauth/token"
	claudeAuthorize   = "https://claude.com/cai/oauth/authorize"
	claudeContentHost = "https://%s.frame.claudeusercontent.com"
)

const (
	claudeClientID      = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
	claudeScopes        = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
	claudeClientVersion = "2.1.323"
	claudeArtifactURL   = "https://claude.ai/code/artifact/"
	errClaudeLogin      = "Could not upload. Please log in to Claude using: artifact -claude-login"
	// Publish limits: the server takes at most 256 manifest entries per request
	// and the CLI sends at most 15 MB inline. Larger publishes would need the
	// prepare/upload flow, which this port leaves out.
	claudeMaxFiles = 255
	claudeMaxBody  = 15 << 20
)

// Content types the server takes as UTF-8 text; the rest go base64-encoded.
var claudeTextTypes = []string{
	"text/html", "text/css", "text/plain", "text/markdown", "text/csv", "text/javascript",
	"application/javascript", "application/json", "application/manifest+json",
	"application/xml", "text/xml", "image/svg+xml",
}

// Content type per extension, as Claude Code assigns it; nothing else is served.
var claudeTypes = map[string]string{
	".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
	".json": "application/json", ".map": "application/json", ".geojson": "application/json",
	".webmanifest": "application/manifest+json", ".txt": "text/plain", ".md": "text/markdown",
	".csv": "text/csv", ".xml": "application/xml", ".svg": "image/svg+xml", ".png": "image/png",
	".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp",
	".avif": "image/avif", ".ico": "image/vnd.microsoft.icon", ".woff": "font/woff",
	".woff2": "font/woff2", ".ttf": "font/ttf", ".otf": "font/otf", ".mp3": "audio/mpeg",
	".wav": "audio/wav", ".ogg": "audio/ogg", ".mp4": "video/mp4", ".webm": "video/webm",
	".pdf": "application/pdf", ".wasm": "application/wasm",
}

// errLogin is reported as errClaudeLogin, whatever command hit it.
var errLogin = errors.New(errClaudeLogin)

// apiError is an HTTP error answer from the Artifacts API.
type apiError struct {
	status int
	body   []byte
}

func (e *apiError) Error() string {
	detail := strings.TrimSpace(string(e.body))
	var parsed map[string]any
	if json.Unmarshal(e.body, &parsed) == nil {
		if inner, ok := parsed["error"].(map[string]any); ok {
			parsed = inner
		}
		var parts []string
		for _, key := range []string{"code", "reason", "error", "message"} {
			if value, ok := parsed[key].(string); ok && value != "" {
				parts = append(parts, value)
			}
		}
		if len(parts) > 0 {
			detail = strings.Join(parts, " - ")
		}
	}
	if len(detail) > 400 {
		detail = detail[:400]
	}
	if detail == "" {
		detail = map[int]string{
			403: "forbidden (the account or organization may not allow Artifacts)",
			404: "no such artifact, or this login can't see it",
			413: "payload too large",
			429: "rate limited or daily publish cap reached",
		}[e.status]
	}
	return fmt.Sprintf("claude.ai answered HTTP %d: %s", e.status, detail)
}

// -- OAuth --------------------------------------------------------------------

type claudeCredentials struct {
	AccessToken  string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
	ExpiresAt    int64  `json:"expiresAt"` // Unix milliseconds
}

// Outside the Stow-managed ~/.config, and separate from any agent's login.
func claudeCredentialsFile() (string, error) {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		dir = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(dir, "artifact", "claude-credentials.json"), nil
}

func readClaudeCredentials(file string) (*claudeCredentials, error) {
	data, err := os.ReadFile(file)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, errLogin
	}
	if err != nil {
		return nil, err
	}
	var creds claudeCredentials
	if json.Unmarshal(data, &creds) != nil || creds.AccessToken == "" || creds.RefreshToken == "" {
		return nil, errLogin
	}
	return &creds, nil
}

func writeClaudeCredentials(file string, creds *claudeCredentials) error {
	if err := os.MkdirAll(filepath.Dir(file), 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(creds)
	if err != nil {
		return err
	}
	temp, err := os.CreateTemp(filepath.Dir(file), ".credentials-*")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	if err := temp.Chmod(0o600); err != nil {
		temp.Close()
		return err
	}
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	return os.Rename(temp.Name(), file)
}

// tokenExchange posts to the OAuth token endpoint. A refusal means the login
// is gone; a network error is reported as itself.
func tokenExchange(body map[string]string, previous *claudeCredentials) (*claudeCredentials, error) {
	body["client_id"] = claudeClientID
	payload, _ := json.Marshal(body)
	client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Post(claudeTokenURL, "application/json", bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("Claude authorization request failed: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode/100 != 2 {
		// 400, 401 and 403: the refresh token was refused; outages and throttling aren't a lost login.
		if body["grant_type"] == "refresh_token" && slices.Contains([]int{400, 401, 403}, response.StatusCode) {
			return nil, errLogin
		}
		return nil, fmt.Errorf("Claude authorization failed: HTTP %d", response.StatusCode)
	}
	var answer struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int64  `json:"expires_in"`
	}
	if err := json.NewDecoder(response.Body).Decode(&answer); err != nil {
		return nil, fmt.Errorf("invalid Claude authorization response: %w", err)
	}
	if answer.RefreshToken == "" && previous != nil {
		answer.RefreshToken = previous.RefreshToken
	}
	if answer.AccessToken == "" || answer.RefreshToken == "" || answer.ExpiresIn <= 0 {
		return nil, errors.New("incomplete Claude authorization response")
	}
	return &claudeCredentials{
		AccessToken:  answer.AccessToken,
		RefreshToken: answer.RefreshToken,
		ExpiresAt:    time.Now().Add(time.Duration(answer.ExpiresIn) * time.Second).UnixMilli(),
	}, nil
}

// claudeToken returns a live access token, refreshing it first when it
// expires within a minute or the server just refused it as rejected.
func claudeToken(rejected string) (string, error) {
	file, err := claudeCredentialsFile()
	if err != nil {
		return "", err
	}
	creds, err := readClaudeCredentials(file)
	if err != nil {
		return "", err
	}
	if creds.ExpiresAt > time.Now().Add(time.Minute).UnixMilli() && creds.AccessToken != rejected {
		return creds.AccessToken, nil
	}
	// Refresh tokens rotate, so two processes refreshing at once would log
	// each other out: hold a lock and re-read before refreshing.
	lock, err := os.OpenFile(file+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return "", err
	}
	defer lock.Close()
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return "", err
	}
	if creds, err = readClaudeCredentials(file); err != nil {
		return "", err
	}
	if creds.ExpiresAt > time.Now().Add(time.Minute).UnixMilli() && creds.AccessToken != rejected {
		return creds.AccessToken, nil
	}
	fresh, err := tokenExchange(map[string]string{"grant_type": "refresh_token", "refresh_token": creds.RefreshToken}, creds)
	if err != nil {
		return "", err
	}
	return fresh.AccessToken, writeClaudeCredentials(file, fresh)
}

// claudeLogin runs the OAuth authorization-code flow with PKCE through a
// loopback callback, and stores the result. Tokens are never printed.
func claudeLogin() error {
	random := func() string {
		value := make([]byte, 32)
		rand.Read(value)
		return base64.RawURLEncoding.EncodeToString(value)
	}
	state, verifier := random(), random()
	challenge := sha256.Sum256([]byte(verifier))

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	redirect := fmt.Sprintf("http://localhost:%d/callback", listener.Addr().(*net.TCPAddr).Port)
	codes := make(chan string, 1)
	failures := make(chan error, 1)
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		switch {
		case r.URL.Path != "/callback":
			http.NotFound(w, r)
		case query.Get("state") != state:
			http.Error(w, "OAuth state mismatch. Return to the authorization page.", http.StatusBadRequest)
		case query.Has("error"):
			fmt.Fprintln(w, "Sign-in declined. Return to your terminal.")
			failures <- errors.New("Claude sign-in was declined")
		case query.Get("code") != "":
			fmt.Fprintln(w, "Authorization received. Return to your terminal.")
			codes <- query.Get("code")
		default:
			http.Error(w, "Missing authorization code.", http.StatusBadRequest)
		}
	})}
	go server.Serve(listener)
	defer server.Close()

	authorize, _ := url.Parse(claudeAuthorize)
	authorize.RawQuery = url.Values{
		"code":                  {"true"},
		"client_id":             {claudeClientID},
		"response_type":         {"code"},
		"redirect_uri":          {redirect},
		"scope":                 {claudeScopes},
		"code_challenge":        {base64.RawURLEncoding.EncodeToString(challenge[:])},
		"code_challenge_method": {"S256"},
		"state":                 {state},
	}.Encode()
	fmt.Fprintf(os.Stderr, "Sign in to Claude for artifact:\n%s\nWaiting for browser authorization...\n", authorize)
	opener := "xdg-open"
	if runtime.GOOS == "darwin" {
		opener = "open"
	}
	exec.Command(opener, authorize.String()).Start()

	var code string
	select {
	case code = <-codes:
	case err := <-failures:
		return err
	case <-time.After(5 * time.Minute):
		return errors.New("Claude sign-in timed out; run artifact -claude-login again")
	}
	creds, err := tokenExchange(map[string]string{
		"grant_type":    "authorization_code",
		"code":          code,
		"redirect_uri":  redirect,
		"code_verifier": verifier,
		"state":         state,
	}, nil)
	if err != nil {
		return err
	}
	file, err := claudeCredentialsFile()
	if err != nil {
		return err
	}
	if err := writeClaudeCredentials(file, creds); err != nil {
		return err
	}
	fmt.Fprintln(os.Stderr, "Logged in to Claude; credentials saved to", file)
	return nil
}

// -- API transport -----------------------------------------------------------

func claudeHeaders(header http.Header) {
	header.Set("anthropic-beta", "oauth-2025-04-20")
	header.Set("Accept", "application/json")
	header.Set("X-Frame-CP", "go")
	header.Set("X-Frame-Surface", "code")
	header.Set("X-Frame-Platform", "cli")
	header.Set("X-Frame-Client-Version", claudeClientVersion)
	header.Set("User-Agent", "artifact/"+claudeClientVersion)
}

// claudeRequest sends one API call and decodes the JSON answer into out.
// A 401 refreshes the token once; a second one means logging in again.
func claudeRequest(method, apiPath string, body any, out any, extra http.Header) error {
	var payload []byte
	if body != nil {
		var err error
		if payload, err = json.Marshal(body); err != nil {
			return err
		}
	}
	token := ""
	for attempt := 0; ; attempt++ {
		var err error
		if token, err = claudeToken(token); err != nil {
			return err
		}
		request, err := http.NewRequest(method, claudeAPI+apiPath, bytes.NewReader(payload))
		if err != nil {
			return err
		}
		claudeHeaders(request.Header)
		request.Header.Set("Authorization", "Bearer "+token)
		if body != nil {
			request.Header.Set("Content-Type", "application/json")
		}
		for name, values := range extra {
			request.Header[name] = values
		}
		client := &http.Client{Timeout: 2 * time.Minute}
		response, err := client.Do(request)
		if err != nil {
			return fmt.Errorf("network error talking to claude.ai: %w", err)
		}
		data, err := io.ReadAll(response.Body)
		response.Body.Close()
		if err != nil {
			return fmt.Errorf("network error talking to claude.ai: %w", err)
		}
		if response.StatusCode == http.StatusUnauthorized {
			if attempt == 0 {
				continue
			}
			return errLogin
		}
		if response.StatusCode/100 != 2 {
			return &apiError{status: response.StatusCode, body: data}
		}
		if out == nil || len(data) == 0 {
			return nil
		}
		if err := json.Unmarshal(data, out); err != nil {
			return fmt.Errorf("unexpected answer from %s %s: %w", method, apiPath, err)
		}
		return nil
	}
}

var (
	claudeUUID   = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
	claudeLinkID = regexp.MustCompile(`claude\.ai/(?:code/)?artifact/([A-Za-z0-9_-]+)`)
)

const base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

// claudeSlug accepts an artifact's UUID or its claude.ai URL, whose ID is the
// UUID itself or, in claude.ai/artifact/<id> links, the UUID in base58.
func claudeSlug(value string) (string, error) {
	candidate := strings.TrimSpace(value)
	if match := claudeLinkID.FindStringSubmatch(candidate); match != nil {
		candidate = match[1]
	}
	if claudeUUID.MatchString(candidate) {
		return strings.ToLower(candidate), nil
	}
	if len(candidate) >= 16 && len(candidate) <= 22 {
		var number [16]byte
		valid := true
		for _, char := range []byte(candidate) {
			digit := strings.IndexByte(base58, char)
			if digit < 0 {
				valid = false
				break
			}
			carry := digit
			for index := 15; index >= 0; index-- {
				carry += int(number[index]) * 58
				number[index] = byte(carry)
				carry >>= 8
			}
			if carry != 0 {
				valid = false
				break
			}
		}
		if valid {
			h := hex.EncodeToString(number[:])
			return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:], nil
		}
	}
	return "", fmt.Errorf("not a Claude artifact ID or URL: %q", value)
}

// -- publish -----------------------------------------------------------------

type claudeEntry struct {
	Content     string `json:"content"`
	ContentType string `json:"contentType"`
}

// claudeManifest reads the files to publish: a directory with a top-level
// index.html (hidden files skipped, relative paths kept), or a single page
// published as index.html. Limits Claude enforces are reported here.
func claudeManifest(root string) (map[string]claudeEntry, string, error) {
	info, err := os.Stat(root)
	if err != nil {
		return nil, "", err
	}
	files := map[string]string{}
	if info.IsDir() {
		err = filepath.WalkDir(root, func(file string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if file != root && strings.HasPrefix(entry.Name(), ".") {
				if entry.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}
			if entry.Type()&fs.ModeSymlink != 0 {
				return fmt.Errorf("%s is a symlink; copy the file in instead", file)
			}
			if !entry.Type().IsRegular() {
				return nil
			}
			relative, err := filepath.Rel(root, file)
			files[filepath.ToSlash(relative)] = file
			return err
		})
		if err != nil {
			return nil, "", err
		}
		if _, ok := files["index.html"]; !ok {
			return nil, "", fmt.Errorf("%s has no top-level index.html, which Claude artifacts require", root)
		}
	} else {
		if ext := strings.ToLower(filepath.Ext(root)); ext != ".html" && ext != ".htm" {
			return nil, "", fmt.Errorf("Claude publishes a single file only as an HTML page; %s is not .html", root)
		}
		files["index.html"] = root
	}
	if len(files) > claudeMaxFiles {
		return nil, "", fmt.Errorf("%d files to publish; Claude artifacts take at most %d per publish", len(files), claudeMaxFiles)
	}

	manifest := map[string]claudeEntry{}
	total := 0
	title := ""
	for _, key := range slices.Sorted(maps.Keys(files)) {
		if len(key) > 512 || strings.ContainsAny(key, "\\%") {
			return nil, "", fmt.Errorf("%s: Claude refuses paths over 512 bytes or containing \\ or %%", key)
		}
		contentType := claudeTypes[strings.ToLower(path.Ext(key))]
		if key == "index.html" {
			contentType = "text/html"
		}
		if contentType == "" {
			return nil, "", fmt.Errorf("%s: Claude artifacts don't serve files of type %q; supported: %s",
				key, path.Ext(key), strings.Join(slices.Sorted(maps.Keys(claudeTypes)), " "))
		}
		data, err := os.ReadFile(files[key])
		if err != nil {
			return nil, "", err
		}
		content := ""
		if slices.Contains(claudeTextTypes, contentType) {
			if !utf8.Valid(data) {
				return nil, "", fmt.Errorf("%s: Claude takes %s only as UTF-8, and it isn't", key, contentType)
			}
			content = string(data)
		} else {
			content = base64.StdEncoding.EncodeToString(data)
		}
		if key == "index.html" {
			if match := regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`).FindSubmatch(data); match != nil {
				title = strings.TrimSpace(string(match[1]))
			}
		}
		encoded, _ := json.Marshal(content)
		total += len(encoded)
		manifest[key] = claudeEntry{Content: content, ContentType: contentType}
	}
	if total > claudeMaxBody {
		return nil, "", fmt.Errorf("the files total %d MB once encoded; Claude takes at most %d MB per publish", total>>20, claudeMaxBody>>20)
	}
	if title == "" {
		title = strings.TrimSuffix(filepath.Base(root), filepath.Ext(root))
	}
	return manifest, title, nil
}

type claudeBoot struct {
	Version    string `json:"ver"`
	AssetToken string `json:"assetToken"`
	Files      []struct {
		Path        string `json:"path"`
		SHA256      string `json:"sha256"`
		ContentType string `json:"contentType"`
	} `json:"files"`
}

func claudeBootRead(slug string) (*claudeBoot, error) {
	var boot claudeBoot
	return &boot, claudeRequest(http.MethodGet, "/api/frame/"+url.PathEscape(slug)+"?via=model_read", nil, &boot, nil)
}

// claudePublish uploads, then shares with the org with comment access. They
// are separate steps: if sharing fails the artifact exists, and publishing
// again with -id retries without creating another.
func claudePublish(id, root string) error {
	manifest, title, err := claudeManifest(root)
	if err != nil {
		return err
	}
	body := map[string]any{"manifest": manifest, "mode": "replace", "title": title}
	if id == "" {
		body["favicon"] = "📄" // required on a first publish
	} else {
		slug, err := claudeSlug(id)
		if err != nil {
			return err
		}
		boot, err := claudeBootRead(slug)
		if err != nil {
			return err
		}
		body["slug"] = slug
		body["baseVersion"] = boot.Version
	}
	attempt := make([]byte, 16)
	rand.Read(attempt)
	var result struct {
		Slug    string `json:"slug"`
		Version string `json:"version"`
	}
	if err := claudeRequest(http.MethodPost, "/api/frame/deploy/direct?attempt_id="+hex.EncodeToString(attempt), body, &result, nil); err != nil {
		return fmt.Errorf("publish: %w", err)
	}
	if result.Slug == "" {
		return errors.New("publish: claude.ai answered without the artifact's ID")
	}
	link := claudeArtifactURL + result.Slug
	// Printed either way: if sharing fails, the artifact still exists.
	fmt.Println(link)
	if err := claudeShareOrg(result.Slug); err != nil {
		fmt.Fprintf(os.Stderr, "artifact: the artifact exists at %s but isn't shared with your organization.\n"+
			"artifact: retry without creating another: artifact publish -id %s '%s'\n", link, link, strings.ReplaceAll(root, "'", `'\''`))
		return err
	}
	return nil
}

type claudePerm struct {
	Read struct {
		Mode  string   `json:"mode"`
		Users []string `json:"users"`
	} `json:"read"`
	OrgReadLevel        string   `json:"orgReadLevel"`
	AssignableReadModes []string `json:"assignableReadModes"`
	ReadModeFrozen      bool     `json:"readModeFrozen"`
	Version             string   `json:"version"`
}

// claudeShareOrg shares with the whole org and checks members can comment:
// Claude Code treats org access as comment unless orgReadLevel is "view".
func claudeShareOrg(slug string) error {
	permPath := "/api/frame/perm/" + url.PathEscape(slug)
	var perm claudePerm
	if err := claudeRequest(http.MethodGet, permPath, nil, &perm, nil); err != nil {
		return err
	}
	switch {
	case perm.Read.Mode == "org":
	case perm.Read.Mode == "public":
		return errors.New("it is public (anyone with the link), not shared with the organization; change it in its Share menu")
	case perm.ReadModeFrozen:
		return errors.New("its audience can't be changed for this account (readModeFrozen)")
	case perm.AssignableReadModes != nil && !slices.Contains(perm.AssignableReadModes, "org"):
		return fmt.Errorf("your plan or organization doesn't allow sharing with the whole organization (allowed: %s)", strings.Join(perm.AssignableReadModes, ", "))
	case perm.Version == "":
		return errors.New("claude.ai answered the sharing settings without a version")
	default:
		users := perm.Read.Users
		if users == nil || perm.Read.Mode == "" || perm.Read.Mode == "owner" {
			users = []string{}
		}
		change := map[string]any{"read": map[string]any{"mode": "org", "users": users}}
		if err := claudeRequest(http.MethodPatch, permPath, change, nil, http.Header{"If-Match": {perm.Version}}); err != nil {
			return err
		}
		perm = claudePerm{}
		if err := claudeRequest(http.MethodGet, permPath, nil, &perm, nil); err != nil {
			return fmt.Errorf("checking the share: %w", err)
		}
	}
	if perm.Read.Mode != "org" {
		return fmt.Errorf("claude.ai reports its audience as %q after sharing, not the organization", perm.Read.Mode)
	}
	if perm.OrgReadLevel == "view" {
		return errors.New("it is shared with the organization view-only, without comment access; turn on commenting in its Share menu on claude.ai")
	}
	return nil
}

// -- pull --------------------------------------------------------------------

func claudePull(id, dest string) error {
	slug, err := claudeSlug(id)
	if err != nil {
		return err
	}
	boot, err := claudeBootRead(slug)
	if err != nil {
		return err
	}
	if boot.AssetToken == "" {
		return errors.New("this login can't read the artifact's files (claude.ai issued no asset token)")
	}
	if len(boot.Files) == 0 {
		return errors.New("the artifact has no files")
	}
	files := map[string]string{}
	for _, file := range boot.Files {
		files[file.Path] = file.SHA256
	}
	host := fmt.Sprintf(claudeContentHost, slug)
	// The content host takes only the short-lived asset token, never the OAuth one.
	client := &http.Client{Timeout: 2 * time.Minute, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	return pullFiles(dest, slices.Sorted(maps.Keys(files)), func(key string) ([]byte, error) {
		request, err := http.NewRequest(http.MethodGet, host+"/_f/"+url.PathEscape(boot.Version)+"/_src/"+escapePath(key)+"?__frame_t="+url.QueryEscape(boot.AssetToken), nil)
		if err != nil {
			return nil, err
		}
		request.Header.Set("User-Agent", "artifact/"+claudeClientVersion)
		response, err := client.Do(request)
		if err != nil {
			// The URL carries the asset token; report only the cause.
			var urlErr *url.Error
			if errors.As(err, &urlErr) {
				err = urlErr.Err
			}
			return nil, fmt.Errorf("network error reading %s: %w", host, err)
		}
		defer response.Body.Close()
		if response.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("HTTP %d reading the published source", response.StatusCode)
		}
		data, err := io.ReadAll(response.Body)
		if err != nil {
			return nil, err
		}
		if sum := sha256.Sum256(data); files[key] != "" && hex.EncodeToString(sum[:]) != files[key] {
			return nil, errors.New("doesn't match its published sha256")
		}
		return data, nil
	})
}

// -- list --------------------------------------------------------------------

func claudeList() ([]listedArtifact, error) {
	var artifacts []listedArtifact
	seen := map[string]bool{}
	for _, rel := range []string{"mine", "shared"} {
		pageToken := ""
		for {
			query := url.Values{"rel": {rel}, "kind": {"page,document"}, "limit": {"200"}}
			if pageToken != "" {
				query.Set("page_token", pageToken)
			}
			var page struct {
				Artifacts []struct {
					ID        string `json:"id"`
					Title     string `json:"title"`
					Kind      string `json:"kind"`
					UpdatedAt string `json:"updated_at"`
					CreatedAt string `json:"created_at"`
				} `json:"artifacts"`
				NextPageToken string `json:"next_page_token"`
			}
			if err := claudeRequest(http.MethodGet, "/api/frame/artifacts?"+query.Encode(), nil, &page, nil); err != nil {
				return nil, err
			}
			for _, row := range page.Artifacts {
				if row.ID == "" || seen[row.ID] {
					continue
				}
				seen[row.ID] = true
				updated := row.UpdatedAt
				if updated == "" {
					updated = row.CreatedAt
				}
				artifacts = append(artifacts, listedArtifact{
					ID: row.ID, URL: claudeArtifactURL + row.ID, Title: row.Title,
					Updated: updated, Owner: map[string]string{"mine": "me", "shared": "shared with me"}[rel],
				})
			}
			if page.NextPageToken == "" || page.NextPageToken == pageToken {
				break
			}
			pageToken = page.NextPageToken
		}
	}
	return artifacts, nil
}

// -- comments ----------------------------------------------------------------

type claudeComments struct {
	Threads []struct {
		ID                string         `json:"id"`
		ResolvedAt        string         `json:"resolved_at"`
		ClaudeActivatedAt string         `json:"claude_activated_at"`
		Anchor            map[string]any `json:"anchor"`
		Comments          []struct {
			ID     string `json:"id"`
			Author struct {
				Account string `json:"account"`
				Role    string `json:"role"`
			} `json:"author"`
			Text       string `json:"text"`
			CreatedAt  string `json:"created_at"`
			ToClaudeAt string `json:"to_claude_at"`
		} `json:"comments"`
	} `json:"threads"`
	Names map[string]string `json:"names"`
}

type comment struct {
	ID        string `json:"id"`
	Author    string `json:"author"`
	Text      string `json:"text"`
	CreatedAt string `json:"created_at"`
	ToClaude  bool   `json:"to_claude"`
}

type thread struct {
	ID           string         `json:"id"`
	Resolved     bool           `json:"resolved"`
	ResolvedAt   string         `json:"resolved_at,omitempty"`
	SentToClaude bool           `json:"sent_to_claude"`
	AttachedTo   string         `json:"attached_to,omitempty"`
	Anchor       map[string]any `json:"anchor,omitempty"`
	Comments     []comment      `json:"comments"`
}

func claudeThreads(slug string) ([]thread, error) {
	var data claudeComments
	if err := claudeRequest(http.MethodGet, "/api/frame/comments/"+url.PathEscape(slug)+"?names=1", nil, &data, nil); err != nil {
		return nil, err
	}
	threads := []thread{}
	for _, raw := range data.Threads {
		t := thread{
			ID: raw.ID, Resolved: raw.ResolvedAt != "", ResolvedAt: raw.ResolvedAt,
			SentToClaude: raw.ClaudeActivatedAt != "", Anchor: raw.Anchor, Comments: []comment{},
		}
		for _, key := range []string{"label", "path", "file", "selector", "quote"} {
			if value, ok := raw.Anchor[key].(string); ok && value != "" {
				t.AttachedTo = value
				break
			}
		}
		for _, c := range raw.Comments {
			author := "Claude"
			if c.Author.Role == "" {
				author = firstNonEmpty(data.Names[c.Author.Account], c.Author.Account, "?")
			}
			t.Comments = append(t.Comments, comment{ID: c.ID, Author: author, Text: c.Text, CreatedAt: c.CreatedAt, ToClaude: c.ToClaudeAt != ""})
		}
		threads = append(threads, t)
	}
	return threads, nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func oneLine(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	if len(text) > 100 {
		return text[:99] + "…"
	}
	return text
}

func claudeCommentsList(id string, all, asJSON bool) error {
	slug, err := claudeSlug(id)
	if err != nil {
		return err
	}
	threads, err := claudeThreads(slug)
	if err != nil {
		return err
	}
	if !all {
		threads = slices.DeleteFunc(threads, func(t thread) bool { return t.Resolved })
	}
	if asJSON {
		return printJSON(threads)
	}
	if len(threads) == 0 {
		fmt.Fprintln(os.Stderr, "No comments.")
	}
	for _, t := range threads {
		var state []string
		if t.Resolved {
			state = append(state, "resolved "+t.ResolvedAt)
		}
		if t.SentToClaude {
			state = append(state, "sent to Claude")
		}
		fmt.Println(strings.TrimSpace("thread " + t.ID + "  " + strings.Join(state, ", ")))
		if t.AttachedTo != "" {
			fmt.Println("  on " + oneLine(t.AttachedTo))
		}
		for _, c := range t.Comments {
			flag := ""
			if c.ToClaude {
				flag = "  [to Claude]"
			}
			fmt.Printf("  [%s] %s: %s%s\n", c.CreatedAt, c.Author, oneLine(c.Text), flag)
		}
		fmt.Println()
	}
	return nil
}

// -- watch -------------------------------------------------------------------

type watchEvent struct {
	Event      string `json:"event"`
	Version    string `json:"version,omitempty"`
	Previous   string `json:"previous,omitempty"`
	Thread     string `json:"thread,omitempty"`
	Comment    string `json:"comment,omitempty"`
	Author     string `json:"author,omitempty"`
	Text       string `json:"text,omitempty"`
	CreatedAt  string `json:"created_at,omitempty"`
	ToClaude   *bool  `json:"to_claude,omitempty"`
	AttachedTo string `json:"attached_to,omitempty"`
	At         string `json:"at,omitempty"`
}

// commentEvents returns what's new in threads since seen, recording it.
func commentEvents(threads []thread, seen map[string]bool) []watchEvent {
	var events []watchEvent
	for _, t := range threads {
		for _, c := range t.Comments {
			if seen[t.ID+"/"+c.ID] {
				continue
			}
			seen[t.ID+"/"+c.ID] = true
			events = append(events, watchEvent{
				Event: "comment", Thread: t.ID, Comment: c.ID, Author: c.Author, Text: c.Text,
				CreatedAt: c.CreatedAt, ToClaude: &c.ToClaude, AttachedTo: t.AttachedTo,
			})
		}
		if t.Resolved && !seen[t.ID+"/resolved"] {
			seen[t.ID+"/resolved"] = true
			events = append(events, watchEvent{Event: "resolved", Thread: t.ID, At: t.ResolvedAt})
		}
	}
	return events
}

// claudeWatch polls and prints what happens after it starts. It only reads:
// it never pulls, republishes, replies or starts anything.
func claudeWatch(ctx context.Context, id string, interval time.Duration, count int, comments, asJSON bool) error {
	slug, err := claudeSlug(id)
	if err != nil {
		return err
	}
	boot, err := claudeBootRead(slug)
	if err != nil {
		return err
	}
	version := boot.Version
	seen := map[string]bool{}
	if comments {
		threads, err := claudeThreads(slug)
		if err != nil {
			return err
		}
		commentEvents(threads, seen)
	}
	fmt.Fprintf(os.Stderr, "artifact: watching %s%s at version %s, every %s\n", claudeArtifactURL, slug, version, interval)
	emitted := 0
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(interval):
		}
		boot, err := claudeBootRead(slug)
		var threads []thread
		if err == nil && comments {
			threads, err = claudeThreads(slug)
		}
		if err != nil {
			var apiErr *apiError
			if errors.Is(err, errLogin) || errors.As(err, &apiErr) && (apiErr.status == 403 || apiErr.status == 404) {
				return err
			}
			fmt.Fprintln(os.Stderr, "artifact: poll failed, retrying:", err)
			continue
		}
		var events []watchEvent
		if boot.Version != version {
			events = append(events, watchEvent{Event: "version", Version: boot.Version, Previous: version})
			version = boot.Version
		}
		events = append(events, commentEvents(threads, seen)...)
		for _, event := range events {
			if asJSON {
				line, _ := json.Marshal(event)
				fmt.Println(string(line))
			} else {
				switch event.Event {
				case "version":
					fmt.Printf("version %s (was %s)\n", event.Version, event.Previous)
				case "resolved":
					fmt.Printf("resolved thread %s\n", event.Thread)
				default:
					flag := ""
					if *event.ToClaude {
						flag = "  [sent to Claude]"
					}
					fmt.Printf("comment thread %s %s: %s%s\n", event.Thread, event.Author, oneLine(event.Text), flag)
				}
			}
			emitted++
			if count > 0 && emitted >= count {
				return nil
			}
		}
	}
}
