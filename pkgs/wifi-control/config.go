package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type Radio struct {
	ID                 string `json:"id"`
	Band               string `json:"band"`
	Enabled            bool   `json:"enabled"`
	Pending            bool   `json:"pending,omitempty"`
	ConfiguredDisabled bool   `json:"configuredDisabled,omitempty"`
	starting           bool
}

type Result struct {
	Radios  []Radio `json:"radios,omitempty"`
	Changed bool    `json:"changed"`
}

type radioController interface {
	operate(context.Context, *bool) (Result, error)
}

type routerConfig struct {
	Name        string            `json:"name"`
	Type        string            `json:"type"`
	URL         string            `json:"url"`
	Fingerprint string            `json:"certificateSHA256,omitempty"`
	Credentials map[string]string `json:"credentials"`
}

type serviceConfig struct {
	Routers map[string]routerConfig `json:"routers"`
}

var identifierPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`)
var credentialPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$`)
var errCredentialsUnavailable = errors.New("router credentials are unavailable")

func loadConfig(path string) (serviceConfig, error) {
	var config serviceConfig
	file, err := os.Open(path)
	if err != nil {
		return config, err
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&config); err != nil {
		return config, errors.New("invalid router configuration JSON")
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return config, errors.New("expected one router configuration object")
	}
	if len(config.Routers) == 0 {
		return config, errors.New("configure at least one router")
	}
	for id, router := range config.Routers {
		if !identifierPattern.MatchString(id) {
			return config, errors.New("router IDs must contain only letters, digits, underscores, or hyphens (1–64 characters)")
		}
		if router.Name == "" {
			router.Name = id
			config.Routers[id] = router
		}
		if router.Type != "zte-http" && router.Type != "openwrt-ubus" {
			return config, fmt.Errorf("router %s: unsupported connection type", id)
		}
		if err := validateRouterURL(router.URL, router.Type == "openwrt-ubus"); err != nil {
			return config, fmt.Errorf("router %s: %w", id, err)
		}
		if _, err := routerHTTPClient(router.Fingerprint); err != nil {
			return config, fmt.Errorf("router %s: %w", id, err)
		}
		passwordAuth := router.Credentials["username"] != "" && router.Credentials["password"] != ""
		tokenAuth := router.Credentials["token"] != ""
		partialPassword := (router.Credentials["username"] != "" || router.Credentials["password"] != "") && !passwordAuth
		if partialPassword || (router.Type == "zte-http" && (!passwordAuth || tokenAuth)) || (router.Type == "openwrt-ubus" && passwordAuth == tokenAuth) {
			return config, fmt.Errorf("router %s: provide username/password references, or an OpenWrt token reference", id)
		}
		for field, reference := range router.Credentials {
			if (field != "username" && field != "password" && field != "token") || !credentialPattern.MatchString(reference) {
				return config, fmt.Errorf("router %s: invalid credential field or reference", id)
			}
		}
	}
	return config, nil
}

// Values in the config refer to credentials supplied by systemd LoadCredential.
func credential(reference string) (string, error) {
	if !credentialPattern.MatchString(reference) {
		return "", errors.New("invalid credential reference")
	}
	if directory := os.Getenv("CREDENTIALS_DIRECTORY"); directory != "" {
		data, err := os.ReadFile(filepath.Join(directory, reference))
		if err == nil {
			value := strings.TrimSuffix(string(data), "\n")
			if value != "" {
				return value, nil
			}
		}
	}
	return "", fmt.Errorf("%w: %s", errCredentialsUnavailable, reference)
}

type configuredController struct {
	config routerConfig
}

func (c configuredController) operate(ctx context.Context, desired *bool) (Result, error) {
	auth := make(map[string]string)
	for field, reference := range c.config.Credentials {
		value, err := credential(reference)
		if err != nil {
			return Result{}, err
		}
		auth[field] = value
	}
	switch c.config.Type {
	case "zte-http":
		router, err := newZTERouter(c.config.URL, auth["username"], auth["password"], c.config.Fingerprint)
		if err != nil {
			return Result{}, err
		}
		defer router.client.CloseIdleConnections()
		return router.operate(ctx, desired)
	case "openwrt-ubus":
		router, err := newOpenWrt(c.config.URL, auth["token"], auth["username"], auth["password"], c.config.Fingerprint)
		if err != nil {
			return Result{}, err
		}
		defer router.client.CloseIdleConnections()
		return router.operate(ctx, desired)
	default:
		return Result{}, errors.New("unsupported router connection type")
	}
}
