-- Created on every start; changes to existing tables need a manual ALTER.
CREATE DATABASE IF NOT EXISTS llm;

-- One row per CLIProxyAPI usage record (one per upstream attempt).
CREATE TABLE IF NOT EXISTS llm.usage
(
    ts DateTime64(3, 'UTC'),
    request_id String,
    trace_id String,
    session_id String,
    parent_session_id String,
    provider LowCardinality(String),
    executor_type LowCardinality(String),
    model LowCardinality(String),
    alias LowCardinality(String),
    response_model LowCardinality(String),
    auth_id LowCardinality(String),
    auth_type LowCardinality(String),
    access_provider LowCardinality(String),
    source LowCardinality(String),
    reasoning_effort LowCardinality(String),
    service_tier LowCardinality(String),
    effective_service_tier LowCardinality(String),
    generate Bool,
    stream Bool,
    latency_ms UInt32,
    ttft_ms UInt32,
    failed Bool,
    failure_status UInt16,
    failure_body String CODEC(ZSTD(3)),
    input_tokens UInt64,
    output_tokens UInt64,
    reasoning_tokens UInt64,
    cached_tokens UInt64,
    cache_read_tokens UInt64,
    cache_creation_tokens UInt64,
    total_tokens UInt64
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (ts, session_id);

-- One row per model execution: the client's request body and the response as
-- delivered downstream (a body, or every stream chunk/WebSocket event in order).
-- Sorted by session so a session's near-identical bodies compress together.
CREATE TABLE IF NOT EXISTS llm.exchanges
(
    ts DateTime64(3, 'UTC'),
    completed_at DateTime64(3, 'UTC'),
    request_id String,
    trace_id String,
    session_id String,
    parent_session_id String,
    execution_session_id String,
    source_format LowCardinality(String),
    to_format LowCardinality(String),
    model LowCardinality(String),
    requested_model LowCardinality(String),
    user_agent LowCardinality(String),
    stream Bool,
    outcome LowCardinality(String),
    status UInt16,
    error String,
    request_body String CODEC(ZSTD(6)),
    response_body String CODEC(ZSTD(6)),
    response_chunks Array(String) CODEC(ZSTD(6)),
    truncated Bool
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (session_id, ts);
