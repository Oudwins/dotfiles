// Records CLIProxyAPI traffic into ClickHouse: one `usage` row per usage record
// and, when bodies are enabled, one `exchanges` row per model execution with the
// client's request body and the response exactly as delivered downstream.
//
// Hook payloads are the host's pluginapi structs JSON-encoded with their Go field
// names; only the fields used here are declared.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	pluginID      = "session-recorder"
	schemaVersion = 7 // 5 drops per-chunk history; 7 lets us skip the before-auth body.

	headerInitIndex = -1
	pendingTTL      = 2 * time.Hour
	flushInterval   = 2 * time.Second
	batchRows       = 500
	batchBytes      = 16 << 20
	queueRows       = 4096
)

type config struct {
	URL          string `yaml:"url"`
	Database     string `yaml:"database"`
	User         string `yaml:"user"`
	PasswordFile string `yaml:"password-file"`
	Bodies       *bool  `yaml:"bodies"`
	MaxBodyBytes int    `yaml:"max-body-bytes"`
}

func parseConfig(raw []byte) (config, error) {
	cfg := config{URL: "http://127.0.0.1:8123", Database: "llm", User: "default", MaxBodyBytes: 64 << 20}
	if err := yaml.Unmarshal(raw, &cfg); err != nil {
		return cfg, fmt.Errorf("parse config: %w", err)
	}
	if cfg.Bodies == nil {
		enabled := true
		cfg.Bodies = &enabled
	}
	return cfg, nil
}

type requestIntercept struct {
	RequestID      string
	TraceID        string
	SourceFormat   string
	ToFormat       string
	Model          string
	RequestedModel string
	Stream         bool
	Headers        http.Header
	Body           []byte
	Metadata       map[string]any
}

type responseIntercept struct {
	RequestID       string
	OriginalRequest []byte
	Body            []byte
	StatusCode      int
}

type streamChunk struct {
	RequestID       string
	OriginalRequest []byte
	Body            []byte
	ChunkIndex      int
}

type completion struct {
	RequestID      string
	TraceID        string
	SourceFormat   string
	Model          string
	RequestedModel string
	Stream         bool
	Outcome        string
	StatusCode     int
	Error          string
	StartedAt      time.Time
	CompletedAt    time.Time
}

type usageRecord struct {
	RequestID            string
	TraceID              string
	Provider             string
	ExecutorType         string
	Model                string
	Alias                string
	ResponseModel        string
	AccessProvider       string
	SessionID            string
	ParentSessionID      string
	AuthID               string
	AuthType             string
	Source               string
	ReasoningEffort      string
	ServiceTier          string
	EffectiveServiceTier string
	Generate             bool
	Stream               bool
	RequestedAt          time.Time
	Latency              time.Duration
	TTFT                 time.Duration
	Failed               bool
	Failure              struct {
		StatusCode int
		Body       string
	}
	Detail struct {
		InputTokens         int64
		OutputTokens        int64
		ReasoningTokens     int64
		CachedTokens        int64
		CacheReadTokens     int64
		CacheCreationTokens int64
		TotalTokens         int64
	}
}

type usageRow struct {
	TS                   time.Time `json:"ts"`
	RequestID            string    `json:"request_id"`
	TraceID              string    `json:"trace_id"`
	SessionID            string    `json:"session_id"`
	ParentSessionID      string    `json:"parent_session_id"`
	Provider             string    `json:"provider"`
	ExecutorType         string    `json:"executor_type"`
	Model                string    `json:"model"`
	Alias                string    `json:"alias"`
	ResponseModel        string    `json:"response_model"`
	AuthID               string    `json:"auth_id"`
	AuthType             string    `json:"auth_type"`
	AccessProvider       string    `json:"access_provider"`
	Source               string    `json:"source"`
	ReasoningEffort      string    `json:"reasoning_effort"`
	ServiceTier          string    `json:"service_tier"`
	EffectiveServiceTier string    `json:"effective_service_tier"`
	Generate             bool      `json:"generate"`
	Stream               bool      `json:"stream"`
	LatencyMS            int64     `json:"latency_ms"`
	TTFTMS               int64     `json:"ttft_ms"`
	Failed               bool      `json:"failed"`
	FailureStatus        int       `json:"failure_status"`
	FailureBody          string    `json:"failure_body"`
	InputTokens          int64     `json:"input_tokens"`
	OutputTokens         int64     `json:"output_tokens"`
	ReasoningTokens      int64     `json:"reasoning_tokens"`
	CachedTokens         int64     `json:"cached_tokens"`
	CacheReadTokens      int64     `json:"cache_read_tokens"`
	CacheCreationTokens  int64     `json:"cache_creation_tokens"`
	TotalTokens          int64     `json:"total_tokens"`
}

type exchangeRow struct {
	TS                 time.Time `json:"ts"`
	CompletedAt        time.Time `json:"completed_at"`
	RequestID          string    `json:"request_id"`
	TraceID            string    `json:"trace_id"`
	SessionID          string    `json:"session_id"`
	ParentSessionID    string    `json:"parent_session_id"`
	ExecutionSessionID string    `json:"execution_session_id"`
	SourceFormat       string    `json:"source_format"`
	ToFormat           string    `json:"to_format"`
	Model              string    `json:"model"`
	RequestedModel     string    `json:"requested_model"`
	UserAgent          string    `json:"user_agent"`
	Stream             bool      `json:"stream"`
	Outcome            string    `json:"outcome"`
	Status             int       `json:"status"`
	Error              string    `json:"error"`
	RequestBody        string    `json:"request_body"`
	ResponseBody       string    `json:"response_body"`
	ResponseChunks     []string  `json:"response_chunks"`
	Truncated          bool      `json:"truncated"`
}

// pending accumulates one execution until request.complete.
type pending struct {
	seen      time.Time
	row       exchangeRow
	request   []byte
	original  bool // request came from the client's raw body, not an interceptor copy
	response  []byte
	chunks    [][]byte
	size      int
	truncated bool
}

type recorder struct {
	cfg    config
	writer *writer

	mu      sync.Mutex
	pending map[string]*pending
}

func newRecorder(cfg config, w *writer) *recorder {
	return &recorder{cfg: cfg, writer: w, pending: map[string]*pending{}}
}

func (r *recorder) bodies() bool { return *r.cfg.Bodies }

// entry returns the pending record for id; callers hold r.mu.
func (r *recorder) entry(id string, now time.Time) *pending {
	p := r.pending[id]
	if p == nil {
		p = &pending{}
		r.pending[id] = p
	}
	p.seen = now
	return p
}

// fits reserves n bytes unless the per-execution limit would be exceeded.
func (r *recorder) fits(p *pending, n int) bool {
	if p.size+n > r.cfg.MaxBodyBytes {
		p.truncated = true
		return false
	}
	p.size += n
	return true
}

func (r *recorder) setRequest(p *pending, body []byte, original bool) {
	if len(body) == 0 || (p.original && !original) {
		return
	}
	p.size -= len(p.request)
	p.request = nil
	if r.fits(p, len(body)) {
		p.request = body
		p.original = original
	}
}

// orNow guards against zero times, which ClickHouse rejects for the whole batch.
func orNow(t time.Time) time.Time {
	if t.IsZero() {
		return time.Now()
	}
	return t
}

func metaString(meta map[string]any, key string) string {
	value, _ := meta[key].(string)
	return value
}

// interceptAfter runs once per credential attempt; the last attempt wins.
func (r *recorder) interceptAfter(raw []byte) error {
	var req requestIntercept
	if err := json.Unmarshal(raw, &req); err != nil {
		return err
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	p := r.entry(req.RequestID, time.Now())
	p.row.TraceID = req.TraceID
	p.row.SourceFormat = req.SourceFormat
	p.row.ToFormat = req.ToFormat
	p.row.Model = req.Model
	p.row.RequestedModel = req.RequestedModel
	p.row.Stream = req.Stream
	p.row.UserAgent = req.Headers.Get("User-Agent")
	p.row.SessionID = metaString(req.Metadata, "canonical_session_id")
	p.row.ParentSessionID = metaString(req.Metadata, "parent_session_id")
	p.row.ExecutionSessionID = metaString(req.Metadata, "execution_session_id")
	r.setRequest(p, req.Body, false)
	return nil
}

func (r *recorder) interceptResponse(raw []byte) error {
	var req responseIntercept
	if err := json.Unmarshal(raw, &req); err != nil {
		return err
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	p := r.entry(req.RequestID, time.Now())
	r.setRequest(p, req.OriginalRequest, true)
	p.size -= len(p.response)
	p.response = nil
	if r.fits(p, len(req.Body)) {
		p.response = req.Body
	}
	return nil
}

func (r *recorder) interceptChunk(raw []byte) error {
	var req streamChunk
	if err := json.Unmarshal(raw, &req); err != nil {
		return err
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	p := r.entry(req.RequestID, time.Now())
	if req.ChunkIndex == headerInitIndex {
		// Sent again when a stream is retried, so start over.
		for _, chunk := range p.chunks {
			p.size -= len(chunk)
		}
		p.chunks = nil
		r.setRequest(p, req.OriginalRequest, true)
		return nil
	}
	if len(req.Body) > 0 && r.fits(p, len(req.Body)) {
		p.chunks = append(p.chunks, req.Body)
	}
	return nil
}

func (r *recorder) complete(raw []byte) error {
	var req completion
	if err := json.Unmarshal(raw, &req); err != nil {
		return err
	}
	r.mu.Lock()
	p := r.pending[req.RequestID]
	delete(r.pending, req.RequestID)
	r.mu.Unlock()
	// Non-model routes such as GET /v1/models also reach the response hooks.
	// Oversized requests are kept as truncated rows.
	if p == nil || (len(p.request) == 0 && !p.truncated) {
		return nil
	}
	row := p.row
	row.CompletedAt = orNow(req.CompletedAt)
	row.TS = req.StartedAt
	if row.TS.IsZero() {
		row.TS = row.CompletedAt
	}
	row.RequestID = req.RequestID
	row.TraceID = req.TraceID
	row.SourceFormat = req.SourceFormat
	row.Model = req.Model
	row.RequestedModel = req.RequestedModel
	row.Stream = req.Stream
	row.Outcome = req.Outcome
	row.Status = req.StatusCode
	row.Error = req.Error
	row.RequestBody = string(p.request)
	row.ResponseBody = string(p.response)
	row.ResponseChunks = make([]string, len(p.chunks))
	for i, chunk := range p.chunks {
		row.ResponseChunks[i] = string(chunk)
	}
	row.Truncated = p.truncated
	r.writer.add("exchanges", row)
	return nil
}

func (r *recorder) usage(raw []byte) error {
	var rec usageRecord
	if err := json.Unmarshal(raw, &rec); err != nil {
		return err
	}
	r.writer.add("usage", usageRow{
		TS:                   orNow(rec.RequestedAt),
		RequestID:            rec.RequestID,
		TraceID:              rec.TraceID,
		SessionID:            rec.SessionID,
		ParentSessionID:      rec.ParentSessionID,
		Provider:             rec.Provider,
		ExecutorType:         rec.ExecutorType,
		Model:                rec.Model,
		Alias:                rec.Alias,
		ResponseModel:        rec.ResponseModel,
		AuthID:               rec.AuthID,
		AuthType:             rec.AuthType,
		AccessProvider:       rec.AccessProvider,
		Source:               rec.Source,
		ReasoningEffort:      rec.ReasoningEffort,
		ServiceTier:          rec.ServiceTier,
		EffectiveServiceTier: rec.EffectiveServiceTier,
		Generate:             rec.Generate,
		Stream:               rec.Stream,
		LatencyMS:            rec.Latency.Milliseconds(),
		TTFTMS:               rec.TTFT.Milliseconds(),
		Failed:               rec.Failed,
		FailureStatus:        rec.Failure.StatusCode,
		FailureBody:          rec.Failure.Body,
		InputTokens:          rec.Detail.InputTokens,
		OutputTokens:         rec.Detail.OutputTokens,
		ReasoningTokens:      rec.Detail.ReasoningTokens,
		CachedTokens:         rec.Detail.CachedTokens,
		CacheReadTokens:      rec.Detail.CacheReadTokens,
		CacheCreationTokens:  rec.Detail.CacheCreationTokens,
		TotalTokens:          rec.Detail.TotalTokens,
	})
	return nil
}

// evict drops executions whose request.complete never arrived.
func (r *recorder) evict(now time.Time) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for id, p := range r.pending {
		if now.Sub(p.seen) > pendingTTL {
			delete(r.pending, id)
		}
	}
}

type queued struct {
	table string
	row   []byte
}

// writer batches rows per table into ClickHouse HTTP inserts. It never blocks
// the proxy: rows are dropped when the queue is full or ClickHouse is down.
type writer struct {
	cfg      config
	password string
	client   *http.Client
	queue    chan queued
	stop     chan struct{}
	done     chan struct{}

	mu      sync.Mutex
	dropped int
}

func newWriter(cfg config) (*writer, error) {
	w := &writer{
		cfg:    cfg,
		client: &http.Client{Timeout: 30 * time.Second},
		queue:  make(chan queued, queueRows),
		stop:   make(chan struct{}),
		done:   make(chan struct{}),
	}
	if cfg.PasswordFile != "" {
		password, err := os.ReadFile(cfg.PasswordFile)
		if err != nil {
			return nil, fmt.Errorf("read password-file: %w", err)
		}
		w.password = strings.TrimSpace(string(password))
	}
	return w, nil
}

func (w *writer) add(table string, row any) {
	encoded, err := json.Marshal(row)
	if err != nil {
		w.drop(1, err)
		return
	}
	select {
	case w.queue <- queued{table, encoded}:
	default:
		w.drop(1, errors.New("queue full"))
	}
}

func (w *writer) drop(n int, err error) {
	w.mu.Lock()
	w.dropped += n
	total := w.dropped
	w.mu.Unlock()
	fmt.Fprintf(os.Stderr, "%s: dropped %d row(s) (%d total): %v\n", pluginID, n, total, err)
}

func (w *writer) run(tick func(time.Time)) {
	defer close(w.done)
	batches := map[string]*bytes.Buffer{}
	rows := 0
	flush := func() {
		for table, buf := range batches {
			if buf.Len() > 0 {
				w.insert(table, buf.Bytes(), bytes.Count(buf.Bytes(), []byte("\n")))
			}
			delete(batches, table)
		}
		rows = 0
	}
	ticker := time.NewTicker(flushInterval)
	defer ticker.Stop()
	size := 0
	for {
		select {
		case item := <-w.queue:
			buf := batches[item.table]
			if buf == nil {
				buf = &bytes.Buffer{}
				batches[item.table] = buf
			}
			buf.Write(item.row)
			buf.WriteByte('\n')
			rows++
			size += len(item.row) + 1
			if rows >= batchRows || size >= batchBytes {
				flush()
				size = 0
			}
		case now := <-ticker.C:
			flush()
			size = 0
			if tick != nil {
				tick(now)
			}
		case <-w.stop:
			for {
				select {
				case item := <-w.queue:
					buf := batches[item.table]
					if buf == nil {
						buf = &bytes.Buffer{}
						batches[item.table] = buf
					}
					buf.Write(item.row)
					buf.WriteByte('\n')
				default:
					flush()
					return
				}
			}
		}
	}
}

func (w *writer) insert(table string, body []byte, rows int) {
	query := url.Values{}
	query.Set("query", fmt.Sprintf("INSERT INTO %s.%s FORMAT JSONEachRow", w.cfg.Database, table))
	query.Set("date_time_input_format", "best_effort")
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(w.cfg.URL, "/")+"/?"+query.Encode(), bytes.NewReader(body))
	if err != nil {
		w.drop(rows, err)
		return
	}
	req.Header.Set("X-ClickHouse-User", w.cfg.User)
	if w.password != "" {
		req.Header.Set("X-ClickHouse-Key", w.password)
	}
	resp, err := w.client.Do(req)
	if err != nil {
		w.drop(rows, err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		var message bytes.Buffer
		_, _ = message.ReadFrom(resp.Body)
		w.drop(rows, fmt.Errorf("%s: %s", resp.Status, strings.TrimSpace(message.String())))
	}
}

func (w *writer) close() {
	close(w.stop)
	select {
	case <-w.done:
	case <-time.After(10 * time.Second):
	}
}
