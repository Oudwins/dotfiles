package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestRouterConfigValidation(t *testing.T) {
	for _, test := range []struct {
		name, id string
		router   routerConfig
		valid    bool
	}{
		{"zte", "digi", routerConfig{Type: "zte-http", URL: "https://192.168.1.1", Credentials: map[string]string{"username": "USER", "password": "PASSWORD"}}, true},
		{"token", "ap-2", routerConfig{Type: "openwrt-ubus", URL: "https://192.168.1.11/ubus", Credentials: map[string]string{"token": "API_TOKEN"}}, true},
		{"password", "ap", routerConfig{Type: "openwrt-ubus", URL: "https://192.168.1.11/ubus", Credentials: map[string]string{"username": "USER", "password": "PASSWORD"}}, true},
		{"id-path", "../bad", routerConfig{Type: "openwrt-ubus", URL: "https://router/ubus", Credentials: map[string]string{"token": "TOKEN"}}, false},
		{"credential-path", "ap", routerConfig{Type: "openwrt-ubus", URL: "https://router/ubus", Credentials: map[string]string{"token": "../secret"}}, false},
		{"unknown-type", "ap", routerConfig{Type: "ssh", URL: "https://router", Credentials: map[string]string{"token": "TOKEN"}}, false},
		{"partial-password", "ap", routerConfig{Type: "openwrt-ubus", URL: "https://router/ubus", Credentials: map[string]string{"username": "USER", "token": "TOKEN"}}, false},
		{"http", "ap", routerConfig{Type: "openwrt-ubus", URL: "http://router/ubus", Credentials: map[string]string{"token": "TOKEN"}}, false},
		{"empty", "ap", routerConfig{Type: "openwrt-ubus", URL: "https://router/ubus"}, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			data, _ := json.Marshal(serviceConfig{Routers: map[string]routerConfig{test.id: test.router}})
			path := filepath.Join(t.TempDir(), "routers.json")
			if err := os.WriteFile(path, data, 0600); err != nil {
				t.Fatal(err)
			}
			config, err := loadConfig(path)
			if (err == nil) != test.valid {
				t.Fatal("unexpected validation result", err)
			}
			if test.valid && config.Routers[test.id].Name != test.id {
				t.Fatal("default display name missing")
			}
		})
	}
}

func TestCredentialsUseReferences(t *testing.T) {
	directory := t.TempDir()
	t.Setenv("CREDENTIALS_DIRECTORY", directory)
	if err := os.WriteFile(filepath.Join(directory, "test-token"), []byte("from-systemd"), 0600); err != nil {
		t.Fatal(err)
	}
	if value, err := credential("test-token"); err != nil || value != "from-systemd" {
		t.Fatal("could not read systemd credential", err)
	}
	t.Setenv("test-token", "from-environment")
	if value, err := credential("test-token"); err != nil || value != "from-systemd" {
		t.Fatal("environment value overrode the systemd credential", err)
	}
	if _, err := credential("unconfigured-token"); err == nil {
		t.Fatal("missing credentials were accepted")
	}
	if _, err := credential("../test-token"); err == nil {
		t.Fatal("credential path traversal was accepted")
	}
}
