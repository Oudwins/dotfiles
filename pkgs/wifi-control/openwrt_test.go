package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type fakeOpenWrt struct {
	enabled   bool
	disabled  bool
	pending   bool
	startSlow bool
	denied    bool
	reject    bool
	missing   bool
	logins    int
	destroys  int
	ups       int
	downs     int
}

func testOpenWrt(t *testing.T, passwordAuth bool) (*openWrt, *fakeOpenWrt) {
	t.Helper()
	fake := &fakeOpenWrt{enabled: true}
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/ubus" || r.Method != http.MethodPost || r.Header.Get("Content-Type") != "application/json" {
			t.Error("unexpected HTTP request")
		}
		var call struct {
			ID     int               `json:"id"`
			Method string            `json:"method"`
			Params []json.RawMessage `json:"params"`
		}
		if err := json.NewDecoder(r.Body).Decode(&call); err != nil || len(call.Params) != 4 || call.Method != "call" {
			t.Fatal("invalid JSON-RPC call", err)
		}
		var token, object, method string
		_ = json.Unmarshal(call.Params[0], &token)
		_ = json.Unmarshal(call.Params[1], &object)
		_ = json.Unmarshal(call.Params[2], &method)
		var args map[string]any
		_ = json.Unmarshal(call.Params[3], &args)
		response := func(result ...any) {
			_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": call.ID, "result": result})
		}
		if object == "session" && method == "login" {
			if token != strings.Repeat("0", 32) || args["username"] != "root" || args["password"] != "test-password" {
				t.Error("wrong login credentials or null session")
			}
			fake.logins++
			response(0, map[string]any{"ubus_rpc_session": "owned-session", "expires": 300})
			return
		}
		if (passwordAuth && token != "owned-session") || (!passwordAuth && token != "provided-token") {
			t.Error("wrong session token")
		}
		if object == "session" && method == "destroy" {
			fake.destroys++
			response(0)
			return
		}
		if object != "network.wireless" || len(args) != 0 {
			t.Error("unexpected object, or a UCI/configuration operation was attempted")
		}
		if fake.denied {
			_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": call.ID,
				"error": map[string]any{"code": -32002, "message": "sensitive-token-value"}})
			return
		}
		switch method {
		case "status":
			if fake.missing {
				response(0, map[string]any{})
				return
			}
			response(0, map[string]any{
				"radio0": map[string]any{"up": fake.enabled, "pending": fake.pending, "autostart": true,
					"disabled": fake.disabled, "config": map[string]any{"band": "2g"},
					"interfaces": []any{map[string]any{"config": map[string]any{"key": "private-wifi-password"}}}},
				"radio1": map[string]any{"up": false, "pending": false, "disabled": true,
					"config": map[string]any{"band": "5g"}},
			})
		case "up", "down":
			if fake.reject {
				response(6)
				return
			}
			if method == "up" {
				fake.ups++
				fake.pending = fake.startSlow
				fake.enabled = !fake.startSlow
			} else {
				fake.downs++
				fake.enabled, fake.pending = false, false
			}
			response(0)
		default:
			t.Error("unexpected wireless method", method)
			response(3)
		}
	}))
	t.Cleanup(server.Close)
	pin := sha256.Sum256(server.Certificate().Raw)
	token := "provided-token"
	if passwordAuth {
		token = ""
	}
	router, err := newOpenWrt(server.URL+"/ubus", token, "root", "test-password", hex.EncodeToString(pin[:]))
	if err != nil {
		t.Fatal(err)
	}
	return router, fake
}

func TestOpenWrtTokenCommandsPreserveDisabledRadios(t *testing.T) {
	router, fake := testOpenWrt(t, false)
	for _, desired := range []bool{true, false, true, true} {
		result, err := router.operate(context.Background(), &desired)
		if err != nil || !allEnabled(result.Radios, desired) {
			t.Fatal("radio operation failed", result, err)
		}
		if result.Radios[1].Enabled || !result.Radios[1].ConfiguredDisabled {
			t.Fatal("configured-off band was enabled")
		}
		data, _ := json.Marshal(result)
		if strings.Contains(string(data), "private-wifi-password") || strings.Contains(string(data), "provided-token") {
			t.Fatal("router response leaked a secret")
		}
	}
	if fake.ups != 1 || fake.downs != 1 || fake.logins != 0 || fake.destroys != 0 {
		t.Fatalf("non-idempotent commands or caller-owned token destroyed: %+v", fake)
	}
}

func TestOpenWrtPasswordAuthCreatesAndDestroysSession(t *testing.T) {
	router, fake := testOpenWrt(t, true)
	if _, err := router.operate(context.Background(), nil); err != nil {
		t.Fatal(err)
	}
	if fake.logins != 1 || fake.destroys != 1 {
		t.Fatal("owned session was not cleaned up")
	}
}

func TestOpenWrtFailureHandling(t *testing.T) {
	for _, name := range []string{"expired-token", "write-denied", "missing-radios", "all-disabled"} {
		t.Run(name, func(t *testing.T) {
			router, fake := testOpenWrt(t, false)
			desired := false
			switch name {
			case "expired-token":
				fake.denied = true
			case "write-denied":
				fake.reject = true
			case "missing-radios":
				fake.missing = true
			case "all-disabled":
				fake.disabled, desired = true, true
			}
			if _, err := router.operate(context.Background(), &desired); err == nil || strings.Contains(err.Error(), "sensitive-token-value") {
				t.Fatal("failure was ignored or response detail leaked", err)
			}
			if fake.ups != 0 || fake.downs != 0 {
				t.Fatal("unexpected radio write")
			}
		})
	}
}

func TestOpenWrtStartupIsReportedAsPending(t *testing.T) {
	router, fake := testOpenWrt(t, false)
	fake.enabled, fake.startSlow = false, true
	on := true
	result, err := router.operate(context.Background(), &on)
	if err != nil || !result.Changed || !result.Radios[0].Pending || result.Radios[0].Enabled {
		t.Fatal("pending startup incorrectly reported", result, err)
	}
	result, err = router.operate(context.Background(), &on)
	if err != nil || result.Changed || fake.ups != 1 {
		t.Fatal("already-pending startup was restarted", result, err)
	}
}
