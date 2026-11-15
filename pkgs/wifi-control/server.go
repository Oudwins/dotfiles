package main

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"mime"
	"net/http"
	"time"
)

//go:embed web/*
var webFiles embed.FS

type schedule struct {
	Timezone string `json:"timezone"`
	On       string `json:"on"`
	Off      string `json:"off"`
	location *time.Location
}

func newSchedule(timezone, on, off string) (schedule, error) {
	location, err := time.LoadLocation(timezone)
	if err != nil {
		return schedule{}, fmt.Errorf("invalid timezone: %w", err)
	}
	for _, value := range []string{on, off} {
		if _, err := time.Parse("15:04", value); err != nil {
			return schedule{}, errors.New("schedule times must be HH:MM")
		}
	}
	if on == off {
		return schedule{}, errors.New("on and off times must differ")
	}
	return schedule{Timezone: timezone, On: on, Off: off, location: location}, nil
}

type event struct {
	At      time.Time `json:"at"`
	Enabled bool      `json:"enabled"`
}

// This is display-only. systemd owns the two independent daily events.
func (s schedule) next(now time.Time) event {
	local := now.In(s.location)
	var next event
	for _, item := range []struct {
		time    string
		enabled bool
	}{{s.On, true}, {s.Off, false}} {
		clock, _ := time.Parse("15:04", item.time)
		at := time.Date(local.Year(), local.Month(), local.Day(), clock.Hour(), clock.Minute(), 0, 0, s.location)
		if !at.After(now) {
			at = at.AddDate(0, 0, 1)
		}
		if next.At.IsZero() || at.Before(next.At) {
			next = event{At: at, Enabled: item.enabled}
		}
	}
	return next
}

type application struct {
	fleet     *fleet
	schedule  schedule
	publicURL string
}

func (a *application) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/config", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"routers": a.fleet.list(), "schedule": a.schedule, "next": a.schedule.next(time.Now())})
	})
	mux.HandleFunc("GET /api/routers/{id}/status", func(w http.ResponseWriter, r *http.Request) {
		a.operation(w, r, nil)
	})
	mux.HandleFunc("POST /api/routers/{id}/wifi", func(w http.ResponseWriter, r *http.Request) {
		if desired := readBoolean(w, r, "enabled"); desired != nil {
			a.operation(w, r, desired)
		}
	})
	mux.HandleFunc("POST /api/routers/{id}/lock", func(w http.ResponseWriter, r *http.Request) {
		locked := readBoolean(w, r, "locked")
		if locked == nil {
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 45*time.Second)
		defer cancel()
		id := r.PathValue("id")
		if err := a.fleet.setLock(ctx, id, *locked); err != nil {
			code := http.StatusInternalServerError
			if errors.Is(err, errUnknownRouter) {
				code = http.StatusNotFound
			}
			slog.Error("could not save schedule lock", "router", id, "error", err)
			writeJSON(w, code, map[string]string{"error": "Could not save the schedule lock. Refresh to check its state."})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"id": id, "locked": *locked})
	})
	mux.HandleFunc("POST /api/schedule", func(w http.ResponseWriter, r *http.Request) {
		desired := readBoolean(w, r, "enabled")
		if desired == nil {
			return
		}
		ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 45*time.Second)
		defer cancel()
		results, failed := a.fleet.scheduled(ctx, *desired)
		code := http.StatusOK
		if failed {
			code = http.StatusBadGateway
		}
		writeJSON(w, code, map[string]any{"routers": results})
	})
	files, _ := fs.Sub(webFiles, "web")
	mux.Handle("GET /", http.FileServerFS(files))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'self'")
		if r.Method == http.MethodPost {
			origin := r.Header.Get("Origin")
			expected := a.publicURL
			if expected == "" {
				expected = "http://" + r.Host
				if r.TLS != nil {
					expected = "https://" + r.Host
				}
			}
			if (origin != "" && origin != expected) || r.Header.Get("Sec-Fetch-Site") == "cross-site" {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "Cross-origin actions are not allowed."})
				return
			}
			mediaType, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
			if mediaType != "application/json" {
				writeJSON(w, http.StatusUnsupportedMediaType, map[string]string{"error": "Expected application/json."})
				return
			}
		}
		mux.ServeHTTP(w, r)
	})
}

func (a *application) operation(w http.ResponseWriter, r *http.Request, desired *bool) {
	parent := r.Context()
	if desired != nil {
		// Switching off Wi-Fi can disconnect the browser that submitted the command.
		parent = context.WithoutCancel(parent)
	}
	ctx, cancel := context.WithTimeout(parent, 45*time.Second)
	defer cancel()
	result, err := a.fleet.operate(ctx, r.PathValue("id"), desired, false)
	if err != nil {
		code := http.StatusBadGateway
		if errors.Is(err, errUnknownRouter) {
			code = http.StatusNotFound
			result.Error = "Unknown router ID."
		} else if result.Error == "" {
			result.Error = "The router operation could not complete. Refresh to check its state."
		}
		writeJSON(w, code, result)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func readBoolean(w http.ResponseWriter, r *http.Request, field string) *bool {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	var input map[string]json.RawMessage
	var value *bool
	if err := decoder.Decode(&input); err != nil || len(input) != 1 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Provide exactly one boolean " + field + " field."})
		return nil
	}
	if err := json.Unmarshal(input[field], &value); err != nil || value == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Provide a boolean " + field + " field."})
		return nil
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Expected one JSON object."})
		return nil
	}
	return value
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
