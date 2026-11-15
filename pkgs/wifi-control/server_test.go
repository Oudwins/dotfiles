package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type stubController struct {
	calls     int
	err       error
	cancelled bool
}

func (s *stubController) operate(ctx context.Context, _ *bool) (Result, error) {
	s.calls++
	s.cancelled = ctx.Err() != nil
	return Result{Radios: []Radio{{ID: "DEV.WIFI.RD1", Band: "2.4GHz", Enabled: true}, {ID: "DEV.WIFI.RD2", Band: "5GHz", Enabled: true}}}, s.err
}

func testApplication(t *testing.T, controller radioController) *application {
	t.Helper()
	schedule, _ := newSchedule("Europe/Madrid", "07:00", "23:00")
	locks, err := loadLocks(filepath.Join(t.TempDir(), "locks.json"))
	if err != nil {
		t.Fatal(err)
	}
	f := newFleet(serviceConfig{Routers: map[string]routerConfig{"digi": {Name: "DIGI", Type: "zte-http", Credentials: map[string]string{"password": "PRIVATE_REFERENCE"}}}}, locks)
	f.routers["digi"].controller = controller
	return &application{fleet: f, schedule: schedule, publicURL: "https://wifi.example"}
}

func TestAcceptedWriteSurvivesBrowserDisconnect(t *testing.T) {
	controller := &stubController{}
	app := testApplication(t, controller)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	r := httptest.NewRequest(http.MethodPost, "/api/routers/digi/wifi", strings.NewReader(`{"enabled":false}`)).WithContext(ctx)
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	app.handler().ServeHTTP(w, r)
	if w.Code != 200 || controller.cancelled {
		t.Fatal("accepted command was cancelled with the disconnected browser")
	}
}

func TestHTTPActions(t *testing.T) {
	for _, test := range []struct {
		name, method, path, body, origin, contentType string
		status, calls                                 int
	}{
		{"page", "GET", "/", "", "", "", 200, 0},
		{"config", "GET", "/api/config", "", "", "", 200, 0},
		{"status", "GET", "/api/routers/digi/status", "", "", "", 200, 1},
		{"button", "POST", "/api/routers/digi/wifi", `{"enabled":false}`, "https://wifi.example", "application/json", 200, 1},
		{"timer", "POST", "/api/schedule", `{"enabled":true}`, "", "application/json", 200, 1},
		{"lock", "POST", "/api/routers/digi/lock", `{"locked":true}`, "", "application/json", 200, 0},
		{"unknown-router", "GET", "/api/routers/missing/status", "", "", "", 404, 0},
		{"cross-origin", "POST", "/api/routers/digi/wifi", `{"enabled":false}`, "https://other.example", "application/json", 403, 0},
		{"cross-origin-lock", "POST", "/api/routers/digi/lock", `{"locked":true}`, "https://other.example", "application/json", 403, 0},
		{"cross-origin-timer", "POST", "/api/schedule", `{"enabled":false}`, "https://other.example", "application/json", 403, 0},
		{"form", "POST", "/api/routers/digi/wifi", "enabled=false", "", "application/x-www-form-urlencoded", 415, 0},
		{"missing-state", "POST", "/api/routers/digi/wifi", `{}`, "", "application/json", 400, 0},
		{"null-state", "POST", "/api/routers/digi/wifi", `{"enabled":null}`, "", "application/json", 400, 0},
		{"wrong-type", "POST", "/api/routers/digi/wifi", `{"enabled":"false"}`, "", "application/json", 400, 0},
		{"extra-field", "POST", "/api/routers/digi/wifi", `{"enabled":true,"schedule":"off"}`, "", "application/json", 400, 0},
		{"extra-object", "POST", "/api/routers/digi/wifi", `{"enabled":true}{"enabled":false}`, "", "application/json", 400, 0},
		{"get-cannot-write", "GET", "/api/routers/digi/wifi", "", "", "", 404, 0},
	} {
		t.Run(test.name, func(t *testing.T) {
			controller := &stubController{}
			app := testApplication(t, controller)
			r := httptest.NewRequest(test.method, test.path, strings.NewReader(test.body))
			r.Header.Set("Origin", test.origin)
			r.Header.Set("Content-Type", test.contentType)
			w := httptest.NewRecorder()
			app.handler().ServeHTTP(w, r)
			if w.Code != test.status || controller.calls != test.calls {
				t.Fatalf("status=%d calls=%d body=%s", w.Code, controller.calls, w.Body)
			}
			if strings.Contains(w.Body.String(), "PRIVATE_REFERENCE") {
				t.Fatal("credential configuration was exposed in an API response")
			}
		})
	}
}

func TestRouterFailureIsAnErrorNotAnOffState(t *testing.T) {
	app := testApplication(t, &stubController{err: errors.New("sensitive upstream detail")})
	w := httptest.NewRecorder()
	app.handler().ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/routers/digi/status", nil))
	if w.Code != 502 || strings.Contains(w.Body.String(), "sensitive") || strings.Contains(w.Body.String(), `"enabled":false`) {
		t.Fatalf("unexpected error response: %s", w.Body)
	}
}

func TestScheduleFollowsMadridClockAcrossDST(t *testing.T) {
	schedule, err := newSchedule("Europe/Madrid", "07:00", "23:00")
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		now, expected string
		enabled       bool
	}{
		{"2026-03-28T23:30:00+01:00", "2026-03-29T07:00:00+02:00", true},
		{"2026-10-24T23:30:00+02:00", "2026-10-25T07:00:00+01:00", true},
		{"2026-10-03T22:00:00+02:00", "2026-10-03T23:00:00+02:00", false},
		{"2026-10-03T23:00:00+02:00", "2026-10-04T07:00:00+02:00", true},
		{"2026-10-04T07:00:00+02:00", "2026-10-04T23:00:00+02:00", false},
	} {
		now, _ := time.Parse(time.RFC3339, test.now)
		next := schedule.next(now)
		if next.At.Format(time.RFC3339) != test.expected || next.Enabled != test.enabled {
			t.Errorf("at %s got %+v", test.now, next)
		}
	}
}
