package main

import (
	"net/http"
	"strings"
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
