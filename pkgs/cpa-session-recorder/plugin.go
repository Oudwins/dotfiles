package main

import (
	"encoding/json"
	"fmt"
	"sync"
)

const abiVersion uint32 = 1

type envelope struct {
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *envelopeError  `json:"error,omitempty"`
}

type envelopeError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type lifecycleRequest struct {
	ConfigYAML []byte `json:"config_yaml"`
}

var (
	stateMu sync.Mutex
	active  *recorder
)

func current() *recorder {
	stateMu.Lock()
	defer stateMu.Unlock()
	return active
}

// configure replaces the active recorder; executions still pending in the old
// one are dropped, which only happens when the plugin config changes.
func configure(raw []byte) (json.RawMessage, error) {
	var req lifecycleRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, fmt.Errorf("decode lifecycle request: %w", err)
	}
	cfg, err := parseConfig(req.ConfigYAML)
	if err != nil {
		return nil, err
	}
	w, err := newWriter(cfg)
	if err != nil {
		return nil, err
	}
	next := newRecorder(cfg, w)
	go w.run(next.evict)

	stateMu.Lock()
	previous := active
	active = next
	stateMu.Unlock()
	if previous != nil {
		previous.writer.close()
	}
	return json.Marshal(registration(*cfg.Bodies))
}

func shutdown() {
	stateMu.Lock()
	previous := active
	active = nil
	stateMu.Unlock()
	if previous != nil {
		previous.writer.close()
	}
}

// registration only asks for body hooks when bodies are recorded, so the host
// skips per-chunk calls entirely otherwise.
func registration(bodies bool) map[string]any {
	return map[string]any{
		"schema_version": schemaVersion,
		"metadata": map[string]any{
			"Name":             pluginID,
			"Version":          "0.1.0",
			"Author":           "Oudwins",
			"GitHubRepository": "https://github.com/Oudwins/dotfiles",
			"ConfigFields":     []any{},
		},
		"capabilities": map[string]bool{
			"usage_plugin":                         true,
			"request_interceptor":                  bodies,
			"request_interceptor_omit_body_before": bodies,
			"request_lifecycle_plugin":             bodies,
			"response_interceptor":                 bodies,
			"response_stream_interceptor":          bodies,
		},
	}
}

// handle dispatches one host call and returns the encoded envelope.
func handle(method string, raw []byte) ([]byte, bool) {
	result, err := dispatch(method, raw)
	if err != nil {
		return errorEnvelope("plugin_error", err.Error()), false
	}
	if result == nil {
		result = json.RawMessage(`{}`)
	}
	out, _ := json.Marshal(envelope{OK: true, Result: result})
	return out, true
}

func dispatch(method string, raw []byte) (json.RawMessage, error) {
	switch method {
	case "plugin.register", "plugin.reconfigure":
		return configure(raw)
	case "plugin.quiesce":
		return nil, nil
	case "plugin.shutdown":
		shutdown()
		return nil, nil
	}
	r := current()
	if r == nil {
		return nil, nil
	}
	switch method {
	case "usage.handle":
		return nil, r.usage(raw)
	case "request.intercept_before":
		return nil, nil
	case "request.intercept_after":
		return nil, r.interceptAfter(raw)
	case "response.intercept_after":
		return nil, r.interceptResponse(raw)
	case "response.intercept_stream_chunk":
		return nil, r.interceptChunk(raw)
	case "request.complete":
		return nil, r.complete(raw)
	}
	return nil, fmt.Errorf("unknown method: %s", method)
}

func errorEnvelope(code, message string) []byte {
	out, _ := json.Marshal(envelope{Error: &envelopeError{Code: code, Message: message}})
	return out
}
