// Command artifact publishes files, such as HTML reports, at a URL others can open.
//
// It has two backends, chosen with ARTIFACT_BACKEND (each machine's Nix
// config sets the default; the variable overrides it; one never falls back to
// the other):
//
//   - s3: publish holds no credentials. It sends plain requests to
//     ARTIFACT_UPLOAD_URL (Agent Vault's router), which adds the upload
//     server's bearer token, and prints links under ARTIFACT_PUBLIC_URL.
//     `artifact serve` is that upload server.
//   - claude: Claude Artifacts on claude.ai, with this CLI's own OAuth login
//     (artifact -claude-login). See claude.go.
package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log"
	"maps"
	"mime"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
)

const usage = `Usage:
  artifact -claude-login
      Log in to claude.ai for the claude backend (separate from any agent's login).
  artifact publish [-id ID-OR-URL] PATH
      Upload a file or a directory (recursively, skipping hidden files, keeping
      relative paths) and print its URL. -id updates an existing artifact in
      place and keeps its URL. On claude, a directory needs a top-level
      index.html, and the artifact is shared with your organization, with
      comment access.
  artifact pull ID-OR-URL DEST
      Download an artifact's files into DEST, which must be new or empty.
  artifact list [-json]
      List artifacts, including ones published from other machines (on
      claude: yours and the ones shared with you).
  artifact comments list ID-OR-URL [-all] [-json]
      Show open comment threads (-all: resolved ones too). claude only.
  artifact watch ID-OR-URL [-interval S] [-count N] [-no-comments] [-json]
      Print new versions, comments and resolved threads as they happen.
      -count exits after N events. claude only.
  artifact serve [flags]
      Run the s3 backend's upload server (see artifact serve -h).

ARTIFACT_BACKEND (s3 or claude) picks the backend.
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "-claude-login", "--claude-login":
		err = claudeLogin()
	case "publish":
		err = publish(os.Args[2:])
	case "pull":
		err = pull(os.Args[2:])
	case "list":
		err = list(os.Args[2:])
	case "comments":
		err = comments(os.Args[2:])
	case "watch":
		err = watch(os.Args[2:])
	case "serve":
		err = serve(os.Args[2:])
	case "-h", "--help", "help":
		fmt.Print(usage)
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	if err != nil {
		if errors.Is(err, errLogin) {
			fmt.Fprintln(os.Stderr, errClaudeLogin)
		} else {
			fmt.Fprintln(os.Stderr, "artifact:", err)
		}
		os.Exit(1)
	}
}

func backend() (string, error) {
	switch value := os.Getenv("ARTIFACT_BACKEND"); value {
	case "", "s3":
		return "s3", nil
	case "claude":
		return "claude", nil
	default:
		return "", fmt.Errorf("ARTIFACT_BACKEND must be s3 or claude, not %q", value)
	}
}

// parseArgs parses flags anywhere among the arguments, as in
// "watch ID -interval 5", and returns the positional ones. It exits with the
// usage unless there are exactly want of them.
func parseArgs(flags *flag.FlagSet, args []string, want int) []string {
	flags.Usage = func() { fmt.Fprint(flags.Output(), usage) }
	var positional []string
	for {
		flags.Parse(args)
		if flags.NArg() == 0 {
			break
		}
		positional = append(positional, flags.Arg(0))
		args = flags.Args()[1:]
	}
	if len(positional) != want {
		flags.Usage()
		os.Exit(2)
	}
	return positional
}

func printJSON(value any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}

func errNotSupported(command string) error {
	return fmt.Errorf("%s is not supported by the s3 backend; it needs ARTIFACT_BACKEND=claude", command)
}

// The form newID generates. Uploads accept no other IDs, so agents can't pick
// a name another agent also uses; -id only reuses an ID it was given.
var validID = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,39}-[0-9a-f]{8}$`)

func publish(args []string) error {
	flags := flag.NewFlagSet("publish", flag.ExitOnError)
	id := flags.String("id", "", "existing artifact to publish into, as its ID or URL (default: a new one)")
	root := parseArgs(flags, args, 1)[0]
	name, err := backend()
	if err != nil {
		return err
	}
	if name == "claude" {
		return claudePublish(*id, root)
	}
	uploadURL, publicURL, err := s3URLs()
	if err != nil {
		return err
	}
	info, err := os.Stat(root)
	if err != nil {
		return err
	}
	if *id == "" {
		*id = newID(root)
	} else if *id, err = s3ID(*id); err != nil {
		return err
	}

	// Keys relative to the artifact, mapped to local paths.
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
			if !entry.Type().IsRegular() {
				return nil
			}
			relative, err := filepath.Rel(root, file)
			files[filepath.ToSlash(relative)] = file
			return err
		})
		if err != nil {
			return err
		}
		if len(files) == 0 {
			return fmt.Errorf("%s has no files to publish", root)
		}
	} else {
		files[filepath.Base(root)] = root
	}

	for _, key := range slices.Sorted(maps.Keys(files)) {
		if err := upload(uploadURL+"/"+escapePath(*id+"/"+key), files[key]); err != nil {
			return fmt.Errorf("upload %s: %w", key, err)
		}
	}

	if !info.IsDir() {
		fmt.Println(publicURL + "/" + escapePath(*id+"/"+filepath.Base(root)))
		return nil
	}
	if _, ok := files["index.html"]; !ok {
		fmt.Fprintln(os.Stderr, "artifact: no index.html, so the URL below lists nothing; link to a file inside it")
	}
	fmt.Println(publicURL + "/" + *id + "/")
	return nil
}

func s3URLs() (string, string, error) {
	uploadURL := strings.TrimRight(os.Getenv("ARTIFACT_UPLOAD_URL"), "/")
	publicURL := strings.TrimRight(os.Getenv("ARTIFACT_PUBLIC_URL"), "/")
	if uploadURL == "" || publicURL == "" {
		return "", "", errors.New("ARTIFACT_UPLOAD_URL and ARTIFACT_PUBLIC_URL must be set")
	}
	return uploadURL, publicURL, nil
}

// s3ID takes an artifact's ID, or its URL under ARTIFACT_PUBLIC_URL.
func s3ID(value string) (string, error) {
	id := value
	if parsed, err := url.Parse(value); err == nil && parsed.Host != "" {
		rest := parsed.Path
		if public, err := url.Parse(strings.TrimRight(os.Getenv("ARTIFACT_PUBLIC_URL"), "/")); err == nil && public.Host == parsed.Host {
			rest = strings.TrimPrefix(rest, public.Path)
		}
		id, _, _ = strings.Cut(strings.TrimPrefix(rest, "/"), "/")
	}
	if !validID.MatchString(id) {
		return "", fmt.Errorf("invalid artifact ID %q: pass the ID of an existing artifact, or its URL (like report-1a2b3c4d)", value)
	}
	return id, nil
}

// newID derives a readable, unique ID from a path: "Q3 Report.html" -> "q3-report-1a2b3c4d".
func newID(file string) string {
	name := strings.TrimSuffix(filepath.Base(file), filepath.Ext(file))
	slug := strings.Trim(regexp.MustCompile(`[^a-z0-9]+`).ReplaceAllString(strings.ToLower(name), "-"), "-")
	if len(slug) > 40 {
		slug = strings.TrimRight(slug[:40], "-")
	}
	if slug == "" {
		slug = "artifact"
	}
	suffix := make([]byte, 4)
	rand.Read(suffix)
	return slug + "-" + hex.EncodeToString(suffix)
}

func upload(target, file string) error {
	body, err := os.Open(file)
	if err != nil {
		return err
	}
	defer body.Close()
	info, err := body.Stat()
	if err != nil {
		return err
	}
	request, err := http.NewRequest(http.MethodPut, target, body)
	if err != nil {
		return err
	}
	// Without a length Go would send the file chunked, which S3 rejects.
	request.ContentLength = info.Size()
	if info.Size() == 0 {
		request.Body = http.NoBody
	}
	if contentType := mime.TypeByExtension(filepath.Ext(file)); contentType != "" {
		request.Header.Set("Content-Type", contentType)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode/100 != 2 {
		message, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		return fmt.Errorf("%s: %s", response.Status, strings.TrimSpace(string(message)))
	}
	return nil
}

func pull(args []string) error {
	positional := parseArgs(flag.NewFlagSet("pull", flag.ExitOnError), args, 2)
	id, dest := positional[0], positional[1]
	name, err := backend()
	if err != nil {
		return err
	}
	if name == "claude" {
		err = claudePull(id, dest)
	} else {
		err = s3Pull(id, dest)
	}
	if err != nil {
		return err
	}
	fmt.Fprintln(os.Stderr, "artifact: pulled into", dest)
	return nil
}

// pullFiles writes each key's bytes under dest, which must be new or empty.
// Keys come from the server, so each is checked before anything is written.
func pullFiles(dest string, keys []string, fetch func(key string) ([]byte, error)) error {
	for _, key := range keys {
		if !validKey("a-00000000/" + key) {
			return fmt.Errorf("refusing to write unsafe path %q", key)
		}
	}
	entries, err := os.ReadDir(dest)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if len(entries) > 0 {
		return fmt.Errorf("%s is not empty; pull into a new or empty directory", dest)
	}
	// Everything is downloaded before anything is written, so a failed pull
	// leaves dest as it was.
	contents := map[string][]byte{}
	for _, key := range keys {
		data, err := fetch(key)
		if err != nil {
			return fmt.Errorf("pull %s: %w", key, err)
		}
		contents[key] = data
	}
	for key, data := range contents {
		file := filepath.Join(dest, filepath.FromSlash(key))
		if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(file, data, 0o644); err != nil {
			return err
		}
	}
	return nil
}

// listedArtifact is one row of `artifact list`, from either backend.
type listedArtifact struct {
	ID      string       `json:"id"`
	URL     string       `json:"url"`
	Title   string       `json:"title,omitempty"`
	Updated string       `json:"updated"`
	Owner   string       `json:"owner,omitempty"`
	Files   []listedFile `json:"files,omitempty"`
}

type listedFile struct {
	Path     string `json:"path"`
	Size     int64  `json:"size"`
	Modified string `json:"modified"`
}

func list(args []string) error {
	flags := flag.NewFlagSet("list", flag.ExitOnError)
	asJSON := flags.Bool("json", false, "print JSON")
	parseArgs(flags, args, 0)
	name, err := backend()
	if err != nil {
		return err
	}
	var artifacts []listedArtifact
	if name == "claude" {
		artifacts, err = claudeList()
	} else {
		artifacts, err = s3List()
	}
	if err != nil {
		return err
	}
	if *asJSON {
		if artifacts == nil {
			artifacts = []listedArtifact{}
		}
		return printJSON(artifacts)
	}
	if len(artifacts) == 0 {
		fmt.Fprintln(os.Stderr, "No artifacts.")
	}
	for _, artifact := range artifacts {
		detail := artifact.Title
		if artifact.Files != nil {
			detail = fmt.Sprintf("%d files", len(artifact.Files))
		}
		if artifact.Owner != "" {
			detail += " (" + artifact.Owner + ")"
		}
		fmt.Printf("%s  %s  %s\n", artifact.URL, artifact.Updated, detail)
	}
	return nil
}

func comments(args []string) error {
	flags := flag.NewFlagSet("comments", flag.ExitOnError)
	all := flags.Bool("all", false, "include resolved threads")
	asJSON := flags.Bool("json", false, "print JSON")
	positional := parseArgs(flags, args, 2)
	if positional[0] != "list" {
		flags.Usage()
		os.Exit(2)
	}
	name, err := backend()
	if err != nil {
		return err
	}
	if name != "claude" {
		return errNotSupported("artifact comments")
	}
	return claudeCommentsList(positional[1], *all, *asJSON)
}

func watch(args []string) error {
	flags := flag.NewFlagSet("watch", flag.ExitOnError)
	interval := flags.Float64("interval", 30, "seconds between polls")
	count := flags.Int("count", 0, "exit after this many events (0: never)")
	noComments := flags.Bool("no-comments", false, "watch for new versions only")
	asJSON := flags.Bool("json", false, "print one JSON object per event")
	id := parseArgs(flags, args, 1)[0]
	name, err := backend()
	if err != nil {
		return err
	}
	if name != "claude" {
		return errNotSupported("artifact watch")
	}
	if *interval <= 0 || *count < 0 {
		return errors.New("-interval must be positive and -count not negative")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	return claudeWatch(ctx, id, time.Duration(*interval*float64(time.Second)), *count, !*noComments, *asJSON)
}

// s3List asks the upload server, which lists the bucket with its own key.
func s3List() ([]listedArtifact, error) {
	uploadURL, publicURL, err := s3URLs()
	if err != nil {
		return nil, err
	}
	response, err := http.Get(uploadURL + "/")
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		message, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		return nil, fmt.Errorf("listing: %s: %s", response.Status, strings.TrimSpace(string(message)))
	}
	var artifacts []listedArtifact
	if err := json.NewDecoder(response.Body).Decode(&artifacts); err != nil {
		return nil, fmt.Errorf("listing: %w", err)
	}
	for index := range artifacts {
		artifacts[index].URL = publicURL + "/" + artifacts[index].ID + "/"
	}
	return artifacts, nil
}

// s3Pull downloads an artifact's files from the public site.
func s3Pull(value, dest string) error {
	id, err := s3ID(value)
	if err != nil {
		return err
	}
	artifacts, err := s3List()
	if err != nil {
		return err
	}
	index := slices.IndexFunc(artifacts, func(artifact listedArtifact) bool { return artifact.ID == id })
	if index < 0 {
		return fmt.Errorf("no artifact %s", id)
	}
	var keys []string
	for _, file := range artifacts[index].Files {
		keys = append(keys, file.Path)
	}
	base := strings.TrimSuffix(artifacts[index].URL, "/")
	return pullFiles(dest, keys, func(key string) ([]byte, error) {
		response, err := http.Get(base + "/" + escapePath(key))
		if err != nil {
			return nil, err
		}
		defer response.Body.Close()
		if response.StatusCode != http.StatusOK {
			return nil, errors.New(response.Status)
		}
		return io.ReadAll(response.Body)
	})
}

type server struct {
	endpoint  *url.URL
	bucket    string
	region    string
	accessKey string
	secretKey string
	token     string
	maxSize   int64
	client    *http.Client
}

func serve(args []string) error {
	flags := flag.NewFlagSet("serve", flag.ExitOnError)
	listen := flags.String("listen", "127.0.0.1:8095", "address to listen on")
	endpoint := flags.String("endpoint", "http://127.0.0.1:9000", "S3 endpoint (path-style)")
	bucket := flags.String("bucket", "artifacts", "bucket uploads are written to")
	region := flags.String("region", "us-east-1", "S3 region requests are signed for")
	accessKey := flags.String("access-key", "", "S3 access key")
	secretKeyFile := flags.String("secret-key-file", "", "file holding the S3 secret key")
	tokenFile := flags.String("token-file", "", "file holding the bearer token uploads must carry")
	maxSize := flags.Int64("max-size", 256<<20, "largest accepted file, in bytes")
	flags.Parse(args)

	target, err := url.Parse(*endpoint)
	if err != nil || target.Host == "" {
		return fmt.Errorf("invalid -endpoint %q", *endpoint)
	}
	s := &server{
		endpoint:  target,
		bucket:    *bucket,
		region:    *region,
		accessKey: *accessKey,
		maxSize:   *maxSize,
		// Uploads go to a local S3 endpoint; never through a proxy from the environment.
		client: &http.Client{Transport: &http.Transport{Proxy: nil}},
	}
	if s.secretKey, err = readSecret(*secretKeyFile); err != nil {
		return err
	}
	if s.token, err = readSecret(*tokenFile); err != nil {
		return err
	}
	if s.accessKey == "" {
		return errors.New("-access-key is required")
	}
	log.Printf("accepting uploads for bucket %s on %s", s.bucket, *listen)
	return http.ListenAndServe(*listen, s)
}

func readSecret(file string) (string, error) {
	if file == "" {
		return "", errors.New("-secret-key-file and -token-file are required")
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return "", err
	}
	secret := strings.TrimSpace(string(data))
	if secret == "" {
		return "", fmt.Errorf("%s is empty", file)
	}
	return secret, nil
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut && !(r.Method == http.MethodGet && r.URL.Path == "/") {
		w.Header().Set("Allow", http.MethodPut)
		http.Error(w, "only PUT, and GET / to list, are supported", http.StatusMethodNotAllowed)
		return
	}
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || subtle.ConstantTimeCompare([]byte(token), []byte(s.token)) != 1 {
		http.Error(w, "invalid or missing bearer token", http.StatusUnauthorized)
		return
	}
	if r.Method == http.MethodGet {
		s.list(w, r)
		return
	}
	key := strings.TrimPrefix(r.URL.Path, "/")
	if !validKey(key) {
		http.Error(w, "invalid path", http.StatusBadRequest)
		return
	}
	if r.ContentLength < 0 {
		http.Error(w, "Content-Length is required", http.StatusLengthRequired)
		return
	}
	if r.ContentLength > s.maxSize {
		http.Error(w, fmt.Sprintf("file is larger than %d bytes", s.maxSize), http.StatusRequestEntityTooLarge)
		return
	}
	contentType := mime.TypeByExtension(path.Ext(key))
	if contentType == "" {
		contentType = r.Header.Get("Content-Type")
	}
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	target := *s.endpoint
	target.Path = "/" + s.bucket + "/" + key
	target.RawPath = "/" + escapePath(s.bucket+"/"+key)
	request, err := http.NewRequestWithContext(r.Context(), http.MethodPut, target.String(), r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	request.ContentLength = r.ContentLength
	if r.ContentLength == 0 {
		request.Body = http.NoBody
	}
	request.Header.Set("Content-Type", contentType)
	request.Header.Set("X-Amz-Content-Sha256", "UNSIGNED-PAYLOAD")
	sign(request, s.accessKey, s.secretKey, s.region, time.Now())

	response, err := s.client.Do(request)
	if err != nil {
		log.Printf("PUT %s: %v", key, err)
		http.Error(w, "storage unavailable", http.StatusBadGateway)
		return
	}
	defer response.Body.Close()
	if response.StatusCode/100 != 2 {
		message, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		log.Printf("PUT %s: storage answered %s: %s", key, response.Status, message)
		http.Error(w, "storage rejected the upload: "+response.Status, http.StatusBadGateway)
		return
	}
	log.Printf("stored %s (%d bytes)", key, r.ContentLength)
	w.WriteHeader(http.StatusCreated)
}

// list answers every artifact in the bucket, its objects grouped by the ID
// their key starts with, most recently updated first. Only the upload
// server's key may list the bucket; anonymous listing stays disabled.
func (s *server) list(w http.ResponseWriter, r *http.Request) {
	byID := map[string]*listedArtifact{}
	continuation := ""
	for {
		query := url.Values{"list-type": {"2"}}
		if continuation != "" {
			query.Set("continuation-token", continuation)
		}
		target := *s.endpoint
		target.Path = "/" + s.bucket
		// SigV4 signs the query with spaces as %20.
		target.RawQuery = strings.ReplaceAll(query.Encode(), "+", "%20")
		request, err := http.NewRequestWithContext(r.Context(), http.MethodGet, target.String(), nil)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		request.Header.Set("X-Amz-Content-Sha256", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
		sign(request, s.accessKey, s.secretKey, s.region, time.Now())
		response, err := s.client.Do(request)
		if err != nil {
			log.Printf("list: %v", err)
			http.Error(w, "storage unavailable", http.StatusBadGateway)
			return
		}
		var page struct {
			Contents []struct {
				Key          string
				Size         int64
				LastModified string
			}
			IsTruncated           bool
			NextContinuationToken string
		}
		if response.StatusCode != http.StatusOK {
			message, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
			response.Body.Close()
			log.Printf("list: storage answered %s: %s", response.Status, message)
			http.Error(w, "storage refused the listing: "+response.Status, http.StatusBadGateway)
			return
		}
		err = xml.NewDecoder(response.Body).Decode(&page)
		response.Body.Close()
		if err != nil {
			log.Printf("list: %v", err)
			http.Error(w, "storage answered an unreadable listing", http.StatusBadGateway)
			return
		}
		for _, object := range page.Contents {
			if !validKey(object.Key) {
				continue
			}
			id, file, _ := strings.Cut(object.Key, "/")
			artifact := byID[id]
			if artifact == nil {
				artifact = &listedArtifact{ID: id}
				byID[id] = artifact
			}
			artifact.Files = append(artifact.Files, listedFile{Path: file, Size: object.Size, Modified: object.LastModified})
			artifact.Updated = max(artifact.Updated, object.LastModified)
		}
		if !page.IsTruncated || page.NextContinuationToken == "" {
			break
		}
		continuation = page.NextContinuationToken
	}
	artifacts := []listedArtifact{}
	for _, artifact := range byID {
		artifacts = append(artifacts, *artifact)
	}
	slices.SortFunc(artifacts, func(a, b listedArtifact) int { return strings.Compare(b.Updated, a.Updated) })
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(artifacts)
}

// validKey accepts slash-separated object keys without empty, "." or ".." segments.
func validKey(key string) bool {
	if key == "" || len(key) > 1024 || strings.ContainsAny(key, "\\\x00") {
		return false
	}
	if id, _, ok := strings.Cut(key, "/"); !ok || !validID.MatchString(id) {
		return false
	}
	for _, segment := range strings.Split(key, "/") {
		if segment == "" || segment == "." || segment == ".." {
			return false
		}
		for _, char := range segment {
			if char < 0x20 || char == 0x7f {
				return false
			}
		}
	}
	return true
}

// escapePath percent-encodes every byte of each segment except SigV4's
// unreserved characters, so the path sent is the one signed.
func escapePath(key string) string {
	segments := strings.Split(key, "/")
	for index, segment := range segments {
		var escaped strings.Builder
		for _, char := range []byte(segment) {
			if 'A' <= char && char <= 'Z' || 'a' <= char && char <= 'z' || '0' <= char && char <= '9' || strings.IndexByte("-_.~", char) >= 0 {
				escaped.WriteByte(char)
			} else {
				fmt.Fprintf(&escaped, "%%%02X", char)
			}
		}
		segments[index] = escaped.String()
	}
	return strings.Join(segments, "/")
}

// sign adds an AWS Signature Version 4 for S3, covering the host and every
// header already set. X-Amz-Content-Sha256 must already hold the payload hash.
func sign(request *http.Request, accessKey, secretKey, region string, now time.Time) {
	timestamp := now.UTC().Format("20060102T150405Z")
	date := timestamp[:8]
	request.Header.Set("X-Amz-Date", timestamp)

	headers := map[string]string{"host": request.URL.Host}
	for name, values := range request.Header {
		headers[strings.ToLower(name)] = strings.TrimSpace(strings.Join(values, ","))
	}
	names := slices.Sorted(maps.Keys(headers))
	var canonicalHeaders strings.Builder
	for _, name := range names {
		canonicalHeaders.WriteString(name + ":" + headers[name] + "\n")
	}
	signedHeaders := strings.Join(names, ";")

	canonicalRequest := strings.Join([]string{
		request.Method,
		request.URL.EscapedPath(),
		request.URL.RawQuery,
		canonicalHeaders.String(),
		signedHeaders,
		request.Header.Get("X-Amz-Content-Sha256"),
	}, "\n")
	scope := date + "/" + region + "/s3/aws4_request"
	hash := sha256.Sum256([]byte(canonicalRequest))
	stringToSign := "AWS4-HMAC-SHA256\n" + timestamp + "\n" + scope + "\n" + hex.EncodeToString(hash[:])

	key := []byte("AWS4" + secretKey)
	for _, part := range []string{date, region, "s3", "aws4_request"} {
		key = hmacSHA256(key, part)
	}
	signature := hex.EncodeToString(hmacSHA256(key, stringToSign))
	request.Header.Set("Authorization", fmt.Sprintf(
		"AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		accessKey, scope, signedHeaders, signature,
	))
}

func hmacSHA256(key []byte, data string) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(data))
	return mac.Sum(nil)
}
