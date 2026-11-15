package main

import (
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func routerHTTPClient(fingerprint string) (*http.Client, error) {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.MaxIdleConnsPerHost = 2
	transport.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	if fingerprint != "" {
		pin, err := hex.DecodeString(fingerprint)
		if err != nil || len(pin) != sha256.Size {
			return nil, errors.New("router certificate fingerprint must be SHA-256 hex")
		}
		// Replace CA validation with an exact pin for a router's self-signed certificate.
		transport.TLSClientConfig.InsecureSkipVerify = true
		transport.TLSClientConfig.VerifyConnection = func(state tls.ConnectionState) error {
			if len(state.PeerCertificates) == 0 {
				return errors.New("router sent no TLS certificate")
			}
			digest := sha256.Sum256(state.PeerCertificates[0].Raw)
			if hex.EncodeToString(digest[:]) != strings.ToLower(fingerprint) {
				return errors.New("router TLS certificate does not match its configured fingerprint")
			}
			return nil
		}
	}
	return &http.Client{
		Transport: transport, Timeout: 15 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}, nil
}

func validateRouterURL(address string, allowPath bool) error {
	u, err := url.Parse(address)
	if err != nil || u.Host == "" || u.Scheme != "https" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return errors.New("router URL must use HTTPS, without user information, query, or fragment")
	}
	if !allowPath && u.Path != "" && u.Path != "/" {
		return errors.New("this connection type requires the router's HTTPS origin")
	}
	return nil
}
