package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type insert struct {
	query, user, key string
	rows             []map[string]any
}

func fakeClickHouse(t *testing.T) (*httptest.Server, func() []insert) {
	t.Helper()
	var mu sync.Mutex
	var inserts []insert
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		got := insert{query: r.URL.Query().Get("query"), user: r.Header.Get("X-ClickHouse-User"), key: r.Header.Get("X-ClickHouse-Key")}
		scanner := bufio.NewScanner(bytes.NewReader(body))
		scanner.Buffer(nil, 1<<26)
		for scanner.Scan() {
			var row map[string]any
			if err := json.Unmarshal(scanner.Bytes(), &row); err != nil {
				t.Errorf("row is not JSON: %v", err)
			}
			got.rows = append(got.rows, row)
		}
		mu.Lock()
		inserts = append(inserts, got)
		mu.Unlock()
	}))
	t.Cleanup(server.Close)
	return server, func() []insert {
		mu.Lock()
		defer mu.Unlock()
		return append([]insert(nil), inserts...)
	}
}

func call(t *testing.T, method string, payload any) map[string]any {
	t.Helper()
	raw, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	out, ok := handle(method, raw)
	var env struct {
		OK     bool
		Result map[string]any
		Error  *envelopeError
	}
	if err := json.Unmarshal(out, &env); err != nil {
		t.Fatalf("%s: bad envelope %s", method, out)
	}
	if !ok || !env.OK {
		t.Fatalf("%s failed: %+v", method, env.Error)
	}
	return env.Result
}

func register(t *testing.T, yaml string) map[string]any {
	t.Helper()
	t.Cleanup(shutdown)
	return call(t, "plugin.register", map[string]any{"config_yaml": []byte(yaml), "schema_version": 10})
}

// rowsFor flushes the writer and returns rows inserted into table.
func rowsFor(t *testing.T, inserts func() []insert, table string) []map[string]any {
	t.Helper()
	shutdown()
	var rows []map[string]any
	for _, in := range inserts() {
		if strings.HasPrefix(in.query, "INSERT INTO llm."+table+" ") {
			rows = append(rows, in.rows...)
		}
	}
	return rows
}

func TestStreamingExchange(t *testing.T) {
	server, inserts := fakeClickHouse(t)
	password := filepath.Join(t.TempDir(), "password")
	if err := os.WriteFile(password, []byte("s3cret\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	register(t, "enabled: true\nurl: "+server.URL+"\nuser: recorder\npassword-file: "+password+"\n")

	call(t, "request.intercept_after", map[string]any{
		"RequestID": "r1", "TraceID": "t1", "SourceFormat": "claude", "ToFormat": "claude",
		"Model": "claude-opus-5-5", "Stream": true,
		"Headers":  map[string][]string{"User-Agent": {"claude-cli/2.0"}, "Authorization": {"Bearer secret"}},
		"Body":     []byte(`{"messages":"rewritten"}`),
		"Metadata": map[string]any{"canonical_session_id": "claude:s1", "parent_session_id": "claude:p1"},
	})
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r1", "ChunkIndex": -1, "OriginalRequest": []byte(`{"messages":"raw"}`)})
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r1", "ChunkIndex": 0, "Body": []byte("data: lost\n\n")})
	// A retried stream starts again with header-init.
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r1", "ChunkIndex": -1, "OriginalRequest": []byte(`{"messages":"raw"}`)})
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r1", "ChunkIndex": 0, "Body": []byte("data: a\n\n")})
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r1", "ChunkIndex": 1, "Body": []byte("data: b\n\n")})
	started := time.Date(2026, 11, 18, 10, 0, 0, 0, time.UTC)
	call(t, "request.complete", map[string]any{
		"RequestID": "r1", "TraceID": "t1", "SourceFormat": "claude", "Model": "claude-opus-5-5",
		"Stream": true, "Outcome": "succeeded", "StatusCode": 200,
		"StartedAt": started, "CompletedAt": started.Add(3 * time.Second),
	})

	rows := rowsFor(t, inserts, "exchanges")
	if len(rows) != 1 {
		t.Fatalf("want 1 exchange, got %d", len(rows))
	}
	row := rows[0]
	for key, want := range map[string]any{
		"request_id": "r1", "session_id": "claude:s1", "parent_session_id": "claude:p1",
		"user_agent": "claude-cli/2.0", "request_body": `{"messages":"raw"}`, "outcome": "succeeded",
		"to_format": "claude", "truncated": false,
	} {
		if row[key] != want {
			t.Errorf("%s = %v, want %v", key, row[key], want)
		}
	}
	chunks, _ := json.Marshal(row["response_chunks"])
	if string(chunks) != `["data: a\n\n","data: b\n\n"]` {
		t.Errorf("response_chunks = %s", chunks)
	}
	if strings.Contains(string(mustJSON(t, row)), "Bearer secret") {
		t.Error("credentials leaked into the row")
	}
	for _, in := range inserts() {
		if in.user != "recorder" || in.key != "s3cret" {
			t.Errorf("auth = %q/%q", in.user, in.key)
		}
	}
}

func TestNonStreamingAndUsage(t *testing.T) {
	server, inserts := fakeClickHouse(t)
	register(t, "url: "+server.URL+"\n")

	call(t, "request.intercept_after", map[string]any{"RequestID": "r2", "Body": []byte(`{"input":"after"}`)})
	call(t, "response.intercept_after", map[string]any{"RequestID": "r2", "OriginalRequest": []byte(`{"input":"raw"}`), "Body": []byte(`{"output":"ok"}`), "StatusCode": 200})
	call(t, "request.complete", map[string]any{"RequestID": "r2", "Outcome": "succeeded", "StatusCode": 200})
	call(t, "usage.handle", map[string]any{
		"RequestID": "u1", "TraceID": "t2", "SessionID": "codex:s2", "Model": "gpt-6-astra",
		"RequestedAt": time.Now(), "Latency": int64(1500 * time.Millisecond), "TTFT": int64(200 * time.Millisecond),
		"Detail": map[string]any{"InputTokens": 10, "OutputTokens": 5, "TotalTokens": 15},
	})

	exchanges := rowsFor(t, inserts, "exchanges")
	if len(exchanges) != 1 || exchanges[0]["request_body"] != `{"input":"raw"}` || exchanges[0]["response_body"] != `{"output":"ok"}` {
		t.Fatalf("exchanges = %v", exchanges)
	}
	usage := rowsFor(t, inserts, "usage")
	if len(usage) != 1 {
		t.Fatalf("want 1 usage row, got %d", len(usage))
	}
	for key, want := range map[string]any{"session_id": "codex:s2", "latency_ms": 1500.0, "ttft_ms": 200.0, "total_tokens": 15.0} {
		if usage[0][key] != want {
			t.Errorf("%s = %v, want %v", key, usage[0][key], want)
		}
	}
}

func TestFailedRequestKeepsAfterAuthBody(t *testing.T) {
	server, inserts := fakeClickHouse(t)
	register(t, "url: "+server.URL+"\n")
	call(t, "request.intercept_after", map[string]any{"RequestID": "r3", "Body": []byte(`{"input":"x"}`)})
	call(t, "request.complete", map[string]any{"RequestID": "r3", "Outcome": "failed", "StatusCode": 429, "Error": "quota"})
	rows := rowsFor(t, inserts, "exchanges")
	if len(rows) != 1 || rows[0]["request_body"] != `{"input":"x"}` || rows[0]["status"] != 429.0 {
		t.Fatalf("rows = %v", rows)
	}
}

func TestSkipsExchangesWithoutRequest(t *testing.T) {
	server, inserts := fakeClickHouse(t)
	register(t, "url: "+server.URL+"\n")
	call(t, "response.intercept_after", map[string]any{"RequestID": "m1", "Body": []byte(`{"object":"list"}`), "StatusCode": 200})
	call(t, "request.complete", map[string]any{"RequestID": "m1", "Outcome": "succeeded"})
	call(t, "request.complete", map[string]any{"RequestID": "unknown", "Outcome": "rejected"})
	if rows := rowsFor(t, inserts, "exchanges"); len(rows) != 0 {
		t.Fatalf("rows = %v", rows)
	}
}

func TestBodyLimit(t *testing.T) {
	server, inserts := fakeClickHouse(t)
	register(t, "url: "+server.URL+"\nmax-body-bytes: 10\n")
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r4", "ChunkIndex": -1, "OriginalRequest": []byte("12345")})
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r4", "ChunkIndex": 0, "Body": []byte("1234")})
	call(t, "response.intercept_stream_chunk", map[string]any{"RequestID": "r4", "ChunkIndex": 1, "Body": []byte("12")})
	call(t, "request.complete", map[string]any{"RequestID": "r4"})
	rows := rowsFor(t, inserts, "exchanges")
	if len(rows) != 1 || rows[0]["truncated"] != true || len(rows[0]["response_chunks"].([]any)) != 1 {
		t.Fatalf("rows = %v", rows)
	}
}

func TestOversizedRequestKeepsTruncatedRow(t *testing.T) {
	server, inserts := fakeClickHouse(t)
	register(t, "url: "+server.URL+"\nmax-body-bytes: 4\n")
	call(t, "request.intercept_after", map[string]any{"RequestID": "r5", "Body": []byte("12345")})
	call(t, "request.complete", map[string]any{"RequestID": "r5", "Outcome": "succeeded"})
	rows := rowsFor(t, inserts, "exchanges")
	if len(rows) != 1 || rows[0]["truncated"] != true || rows[0]["request_body"] != "" {
		t.Fatalf("rows = %v", rows)
	}
}

func TestBodiesDisabledOnlyRegistersUsage(t *testing.T) {
	server, _ := fakeClickHouse(t)
	result := register(t, "url: "+server.URL+"\nbodies: false\n")
	capabilities := result["capabilities"].(map[string]any)
	if capabilities["usage_plugin"] != true || capabilities["response_stream_interceptor"] != false || capabilities["request_interceptor"] != false {
		t.Fatalf("capabilities = %v", capabilities)
	}
	if result["schema_version"] != float64(schemaVersion) {
		t.Fatalf("schema_version = %v", result["schema_version"])
	}
}

func TestEvictsAbandonedExecutions(t *testing.T) {
	r := newRecorder(config{MaxBodyBytes: 1 << 20}, nil)
	r.pending["old"] = &pending{seen: time.Now().Add(-3 * time.Hour)}
	r.pending["new"] = &pending{seen: time.Now()}
	r.evict(time.Now())
	if _, ok := r.pending["old"]; ok {
		t.Error("old execution kept")
	}
	if _, ok := r.pending["new"]; !ok {
		t.Error("new execution evicted")
	}
}

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	out, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return out
}
