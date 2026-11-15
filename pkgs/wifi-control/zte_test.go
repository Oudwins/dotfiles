package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"
)

type fakeRouter struct {
	mu            sync.Mutex
	enabled       [2]bool
	writes        int
	logouts       int
	active        bool
	malformed     bool
	rejectWrite   bool
	wrongPassword bool
}

func testRouter(t *testing.T) (*zteRouter, *fakeRouter) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKIXPublicKey(&key.PublicKey)
	public := string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}))
	fake := &fakeRouter{enabled: [2]bool{true, true}}
	const token = "page-token"
	escaped := `"`
	for _, character := range []byte(token) {
		escaped += fmt.Sprintf(`\x%02x`, character)
	}
	escaped += `"`
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fake.mu.Lock()
		defer fake.mu.Unlock()
		tag := r.URL.Query().Get("_tag")
		if tag == "" {
			if !fake.active {
				http.SetCookie(w, &http.Cookie{Name: "SID", Value: "test-session", Path: "/"})
				fmt.Fprint(w, "<title>H3600 V9</title>")
			} else {
				fmt.Fprintf(w, `var pubKey = %s; var _sessionTmpToken = ""; _sessionTmpToken = %s;`, strconv.Quote(public), escaped)
			}
			return
		}
		cookie, err := r.Cookie("SID")
		if err != nil || cookie.Value != "test-session" {
			t.Error("missing session cookie")
			http.Error(w, "missing session", http.StatusForbidden)
			return
		}
		switch tag {
		case "login_entry":
			if r.Method == http.MethodGet {
				_ = json.NewEncoder(w).Encode(map[string]any{"sess_token": "login-token", "lockingTime": "0"})
				return
			}
			_ = r.ParseForm()
			expected := sha256.Sum256([]byte("passwordchallenge"))
			if fake.active {
				t.Error("concurrent router sessions")
			}
			valid := r.Form.Get("Username") == "test-user" && r.Form.Get("Password") == hex.EncodeToString(expected[:]) && r.Form.Get("_sessionTOKEN") == "login-token" && !fake.wrongPassword
			fake.active = valid
			_ = json.NewEncoder(w).Encode(map[string]any{"login_need_refresh": valid, "sess_token": "post-login"})
		case "login_token":
			fmt.Fprint(w, "<root><token>challenge</token></root>")
		case "logout_entry":
			_ = r.ParseForm()
			if r.Form.Get("_sessionTOKEN") != token {
				t.Error("logout did not use decoded page token")
			}
			fake.logouts++
			fake.active = false
			fmt.Fprint(w, `{"need_refresh":true}`)
		case "wlanBasic":
			fmt.Fprintf(w, "_sessionTmpToken = %s;", escaped)
		case "wlan_basiconoff_lua.lua":
			if !fake.active {
				http.Error(w, "unauthorized", http.StatusForbidden)
				return
			}
			if r.Method == http.MethodPost {
				body, _ := io.ReadAll(r.Body)
				fields, _ := url.ParseQuery(string(body))
				check, _ := base64.StdEncoding.DecodeString(r.Header.Get("Check"))
				decoded, err := rsa.DecryptPKCS1v15(rand.Reader, key, check)
				digest := sha256.Sum256(body)
				if err != nil || string(decoded) != hex.EncodeToString(digest[:]) {
					t.Error("invalid request-check header")
				}
				if fields.Get("_sessionTOKEN") != token || fields.Get("IF_ACTION") != "Apply" {
					t.Error("invalid radio write token or action")
				}
				for index, band := range []string{"2.4GHz", "5GHz"} {
					suffix := "_" + strconv.Itoa(index)
					if fields.Get("_InstID"+suffix) != fmt.Sprintf("DEV.WIFI.RD%d", index+1) || fields.Get("Band"+suffix) != band {
						t.Error("wrong radio instance")
					}
					value := fields.Get("RadioStatus" + suffix)
					if value != "0" && value != "1" {
						t.Error("missing explicit radio state")
					}
					if !fake.rejectWrite {
						fake.enabled[index] = value == "1"
					}
				}
				fake.writes++
				if fake.rejectWrite {
					fmt.Fprint(w, "<root><IF_ERRORSTR>FAIL</IF_ERRORSTR></root>")
					return
				}
			}
			fmt.Fprint(w, "<root><IF_ERRORSTR>SUCC</IF_ERRORSTR><OBJ_WLANSETTING_ID>")
			for index, band := range []string{"2.4GHz", "5GHz"} {
				if fake.malformed && index == 1 {
					continue
				}
				state := 0
				if fake.enabled[index] {
					state = 1
				}
				fmt.Fprintf(w, "<Instance><ParaName>_InstID</ParaName><ParaValue>DEV.WIFI.RD%d</ParaValue><ParaName>Band</ParaName><ParaValue>%s</ParaValue><ParaName>RadioStatus</ParaName><ParaValue>%d</ParaValue></Instance>", index+1, band, state)
			}
			fmt.Fprint(w, "</OBJ_WLANSETTING_ID></root>")
		default:
			t.Errorf("unexpected endpoint %s", tag)
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)
	pin := sha256.Sum256(server.Certificate().Raw)
	router, err := newZTERouter(server.URL, "test-user", "password", hex.EncodeToString(pin[:]))
	if err != nil {
		t.Fatal(err)
	}
	return router, fake
}

func TestRadioCommandsAndManualTimeline(t *testing.T) {
	router, fake := testRouter(t)
	// Manual on at 22:00, timer off at 23:00, manual on at 23:30,
	// timer on at 07:00, then timer off at 23:00.
	for index, enabled := range []bool{true, false, true, true, false} {
		result, err := router.operate(context.Background(), &enabled)
		if err != nil {
			t.Fatal(err)
		}
		if !allEnabled(result.Radios, enabled) {
			t.Fatalf("step %d: unexpected radio states", index)
		}
		if result.Changed != (index != 0 && index != 3) {
			t.Fatalf("step %d: wrong idempotency result", index)
		}
		if _, err := router.operate(context.Background(), nil); err != nil {
			t.Fatal(err)
		}
	}
	if fake.writes != 3 || fake.logouts != 10 {
		t.Fatalf("writes=%d logouts=%d", fake.writes, fake.logouts)
	}
}

func TestRouterFailuresDoNotClaimSuccess(t *testing.T) {
	for _, test := range []string{"missing-radio", "write-rejected", "wrong-password", "wrong-pin"} {
		t.Run(test, func(t *testing.T) {
			router, fake := testRouter(t)
			switch test {
			case "missing-radio":
				fake.malformed = true
			case "write-rejected":
				fake.rejectWrite = true
			case "wrong-password":
				fake.wrongPassword = true
			case "wrong-pin":
				var err error
				router, err = newZTERouter(router.baseURL, "test-user", "password", strings.Repeat("0", 64))
				if err != nil {
					t.Fatal(err)
				}
			}
			off := false
			if _, err := router.operate(context.Background(), &off); err == nil {
				t.Fatal("expected operation to fail")
			}
			if fake.enabled != [2]bool{true, true} {
				t.Fatal("unexpected radio change")
			}
			if test != "write-rejected" && fake.writes != 0 {
				t.Fatal("unexpected settings write")
			}
		})
	}
}

func TestRouterOperationsAreSerialized(t *testing.T) {
	router, _ := testRouter(t)
	var group sync.WaitGroup
	for range 5 {
		group.Go(func() {
			if _, err := router.operate(context.Background(), nil); err != nil {
				t.Error(err)
			}
		})
	}
	group.Wait()
}

func TestMixedBandsAreBothSet(t *testing.T) {
	router, fake := testRouter(t)
	fake.enabled = [2]bool{true, false}
	on := true
	result, err := router.operate(context.Background(), &on)
	if err != nil || !result.Changed || !allEnabled(result.Radios, true) || fake.writes != 1 {
		t.Fatalf("mixed-band write failed: result=%+v error=%v writes=%d", result, err, fake.writes)
	}
}

func TestCancelledOperationDoesNotContactRouter(t *testing.T) {
	router, fake := testRouter(t)
	router.gate <- struct{}{}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := router.operate(ctx, nil); err != context.Canceled {
		t.Fatalf("expected cancellation, got %v", err)
	}
	<-router.gate
	if fake.logouts != 0 || fake.writes != 0 {
		t.Fatal("cancelled queued operation contacted router")
	}
}
