// Command artifact publishes files, such as HTML reports, at a URL others can open.
//
//	artifact publish [-id ID] PATH   upload a file or directory and print its URL
//	artifact serve [flags]           accept authenticated uploads and write them to S3
//
// publish holds no credentials. It sends plain PUTs to ARTIFACT_UPLOAD_URL
// (Agent Vault's router), which adds the upload server's bearer token, and
// prints links under ARTIFACT_PUBLIC_URL. Each machine sets both variables, so
// machines can publish to different backends.
package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
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
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
)

const usage = `Usage:
  artifact publish [-id ID] PATH
      Upload a file or a directory (recursively, skipping hidden files) and
      print its URL. A directory's URL serves its index.html. Without -id a
      new ID is generated from PATH; -id takes an existing artifact's ID, from
      its URL, and replaces files of the same name in it.
  artifact serve [flags]
      Run the upload server (see artifact serve -h).
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "publish":
		err = publish(os.Args[2:])
	case "serve":
		err = serve(os.Args[2:])
	case "-h", "--help", "help":
		fmt.Print(usage)
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "artifact:", err)
		os.Exit(1)
	}
}

// The form newID generates. Uploads accept no other IDs, so agents can't pick
// a name another agent also uses; -id only reuses an ID it was given.
var validID = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,39}-[0-9a-f]{8}$`)

func publish(args []string) error {
	flags := flag.NewFlagSet("publish", flag.ExitOnError)
	id := flags.String("id", "", "existing artifact ID to publish into, from its URL (default: a new one generated from PATH)")
	flags.Usage = func() { fmt.Fprint(flags.Output(), usage) }
	flags.Parse(args)
	if flags.NArg() != 1 {
		flags.Usage()
		os.Exit(2)
	}
	uploadURL := strings.TrimRight(os.Getenv("ARTIFACT_UPLOAD_URL"), "/")
	publicURL := strings.TrimRight(os.Getenv("ARTIFACT_PUBLIC_URL"), "/")
	if uploadURL == "" || publicURL == "" {
		return errors.New("ARTIFACT_UPLOAD_URL and ARTIFACT_PUBLIC_URL must be set")
	}
	root := flags.Arg(0)
	info, err := os.Stat(root)
	if err != nil {
		return err
	}
	if *id == "" {
		*id = newID(root)
	} else if !validID.MatchString(*id) {
		return fmt.Errorf("invalid -id %q: pass the ID of an existing artifact, from its URL (like report-1a2b3c4d)", *id)
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
	if r.Method != http.MethodPut {
		w.Header().Set("Allow", http.MethodPut)
		http.Error(w, "only PUT is supported", http.StatusMethodNotAllowed)
		return
	}
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || subtle.ConstantTimeCompare([]byte(token), []byte(s.token)) != 1 {
		http.Error(w, "invalid or missing bearer token", http.StatusUnauthorized)
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
