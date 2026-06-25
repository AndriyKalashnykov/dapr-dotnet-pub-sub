#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Compose-based e2e: brings producer + consumer + Dapr sidecars + Kafka up
# via `docker compose --wait`, exercises pub/sub through real Dapr sidecars,
# and asserts subscription routing via the consumer container's stdout.
#
# Replaces the older e2e-sidecar.sh flow (background `dapr run -f .` + log
# file grep), which depended on the local Dapr CLI lifecycle.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load committed defaults (.env.example uses ${VAR:-default} forms so an inherited
# env / `make VAR=…` override wins) then an optional gitignored .env override.
# shellcheck source=/dev/null
load_env() { [ -f "$1" ] && { set -a; . "$1"; set +a; }; return 0; }
load_env "$REPO_ROOT/.env.example"
load_env "$REPO_ROOT/.env"

PRODUCER_HOST_PORT="${PRODUCER_HOST_PORT:-5232}"
PRODUCER_DAPR_HTTP_PORT="${PRODUCER_DAPR_HTTP_PORT:-3532}"
JAEGER_HOST_PORT="${JAEGER_HOST_PORT:-16686}"
JAEGER_POLL_SECONDS="${JAEGER_POLL_SECONDS:-45}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"
CURL_MAX_TIME="${CURL_MAX_TIME:-5}"
OTEL_PRODUCER_SERVICE="${OTEL_PRODUCER_SERVICE:-producer}"
OTEL_CONSUMER_SERVICE="${OTEL_CONSUMER_SERVICE:-consumer}"

PRODUCER_URL="${PRODUCER_URL:-http://localhost:${PRODUCER_HOST_PORT}}"
JAEGER_API="${JAEGER_API:-http://localhost:${JAEGER_HOST_PORT}}"
COMPOSE_DIR="${COMPOSE_DIR:-$REPO_ROOT/compose}"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
CONSUMER_CONTAINER="${CONSUMER_CONTAINER:-e2e-consumer}"
PROPAGATION_TIMEOUT="${PROPAGATION_TIMEOUT:-60}"
PASS=0
FAIL=0

cleanup() {
    echo ""
    echo "--- Cleaning up Compose stack ---"
    docker compose --file "$COMPOSE_FILE" down --remove-orphans --volumes >/dev/null 2>&1 || true
}
trap cleanup EXIT

assert_status() {
    local method="$1" url="$2" expected="$3" body="${4:-}"
    local opts=(-s -o /dev/null -w '%{http_code}' -X "$method")
    [[ -n "$body" ]] && opts+=(-H 'Content-Type: application/json' -d "$body")
    local status
    status=$(curl "${opts[@]}" "$url")
    if [[ "$status" == "$expected" ]]; then
        echo "PASS: $method $url -> $status"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $method $url -> $status (expected $expected)"
        FAIL=$((FAIL + 1))
    fi
}

# Wait until the consumer container's stdout contains the expected line,
# polling `docker logs` rather than tailing a host log file.
wait_log() {
    local label="$1" pattern="$2"
    local deadline=$(( $(date +%s) + PROPAGATION_TIMEOUT ))
    while [[ $(date +%s) -lt $deadline ]]; do
        if docker logs "$CONSUMER_CONTAINER" 2>&1 | grep -qF "$pattern"; then
            echo "PASS: consumer received '$label'"
            PASS=$((PASS + 1))
            return 0
        fi
        sleep 1
    done
    echo "FAIL: consumer never received '$label' within ${PROPAGATION_TIMEOUT}s"
    FAIL=$((FAIL + 1))
}

# Two-stage OTel check: a service name registers on its first-ever span and never
# deregisters, so /api/services alone passes against stale state. Assert BOTH the
# service is registered AND a trace was recorded during THIS run. With app-side
# OpenTelemetry the producer's own /send HTTP handler is traced, so driving the
# real publish endpoint (not a sidecar-API workaround) generates the span.
assert_traces_delivering() {
    for _ in 1 2 3 4 5; do
        curl -s -o /dev/null --max-time "$CURL_MAX_TIME" -X POST "$PRODUCER_URL/send" \
            -H 'Content-Type: application/json' \
            -d '{"id":"trace001-0000-0000-0000-000000000001","timeStamp":"2025-09-26T02:52:04.835Z","type":"1"}' || true
    done
    local deadline=$(( $(date +%s) + JAEGER_POLL_SECONDS ))
    local seen_svc="" seen_trace=""
    while [[ $(date +%s) -lt $deadline ]]; do
        if [[ "$seen_svc" != yes ]] && curl -sf --max-time "$CURL_MAX_TIME" \
                "$JAEGER_API/api/services" 2>/dev/null | grep -q "\"$OTEL_PRODUCER_SERVICE\""; then
            seen_svc=yes
        fi
        if [[ "$seen_svc" == yes && "$seen_trace" != yes ]] && curl -sf --max-time "$CURL_MAX_TIME" \
                "$JAEGER_API/api/traces?service=$OTEL_PRODUCER_SERVICE&limit=1" 2>/dev/null | grep -q '"traceID"'; then
            seen_trace=yes; break
        fi
        sleep "$POLL_INTERVAL"
    done
    if [[ "$seen_svc" == yes && "$seen_trace" == yes ]]; then
        echo "PASS: OTel traces delivering to Jaeger (service '$OTEL_PRODUCER_SERVICE' registered + trace recorded this run)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: OTel traces not delivering (service=${seen_svc:-no} trace=${seen_trace:-no}) within ${JAEGER_POLL_SECONDS}s"
        FAIL=$((FAIL + 1))
    fi
}

# Exercise the producer's 500 error path through REAL Kestrel by stopping the
# Dapr sidecar so the publish fails. Integration tests assert this contract on
# TestServer, which can mask a dropped Content-Type header; only a real-Kestrel
# e2e proves application/problem+json survives on the wire. Runs LAST (it stops
# the sidecar); the cleanup trap tears the stack down afterward.
assert_problem_json_on_publish_failure() {
    docker compose --file "$COMPOSE_FILE" stop producer-dapr >/dev/null 2>&1 || true
    sleep 2
    local tmph status ctype
    tmph=$(mktemp)
    status=$(curl -s -o /dev/null -D "$tmph" -w '%{http_code}' --max-time "$CURL_MAX_TIME" \
        -X POST "$PRODUCER_URL/send" -H 'Content-Type: application/json' \
        -d '{"id":"err00001-0000-0000-0000-000000000001","timeStamp":"2025-09-26T02:52:04.835Z","type":"1"}' 2>/dev/null || true)
    ctype=$(tr -d '\r' < "$tmph" | awk -F': ' 'tolower($1)=="content-type"{print $2; exit}')
    rm -f "$tmph"
    if [[ "$status" == 500 && "$ctype" == application/problem+json* ]]; then
        echo "PASS: publish with sidecar down -> 500 ($ctype)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: publish with sidecar down -> status=$status content-type='$ctype' (expected 500 application/problem+json)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Bringing up Compose stack ==="
docker compose --file "$COMPOSE_FILE" up -d --wait --quiet-pull

echo ""
echo "=== Smoke checks ==="
assert_status GET "$PRODUCER_URL/dapr/config" 200

echo ""
echo "--- Publishing messages via /send ---"
assert_status POST "$PRODUCER_URL/send" 202 \
    '{"id":"e2e00001-0000-0000-0000-000000000001","timeStamp":"2025-09-26T02:52:04.835Z","type":"1"}'
assert_status POST "$PRODUCER_URL/send" 202 \
    '{"id":"e2e00002-0000-0000-0000-000000000002","timeStamp":"2025-09-26T02:52:04.835Z","type":"2"}'
assert_status POST "$PRODUCER_URL/send" 202 \
    '{"id":"e2e00003-0000-0000-0000-000000000003","timeStamp":"2025-09-26T02:52:04.835Z","type":"0"}'
assert_status POST "$PRODUCER_URL/send" 202 \
    '{"id":"e2e00005-0000-0000-0000-000000000005","timeStamp":"2025-09-26T02:52:04.835Z","type":"99"}'

echo ""
echo "--- Publishing messages via /sendasbytes ---"
assert_status POST "$PRODUCER_URL/sendasbytes" 202 \
    '{"id":"e2e00004-0000-0000-0000-000000000004","timeStamp":"2025-09-27T02:52:04.835Z","type":"1"}'

echo ""
echo "--- Negative cases ---"
assert_status POST "$PRODUCER_URL/send" 400 '{not-json}'
# Unsupported media type (text/plain) — assert_status forces application/json, so curl inline.
neg_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$CURL_MAX_TIME" \
    -X POST "$PRODUCER_URL/send" -H 'Content-Type: text/plain' -d 'not json')
if [[ "$neg_status" == 415 ]]; then
    echo "PASS: POST /send text/plain -> 415"; PASS=$((PASS + 1))
else
    echo "FAIL: POST /send text/plain -> $neg_status (expected 415)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Verifying subscription routing (consumer stdout, ${PROPAGATION_TIMEOUT}s budget) ---"
wait_log "type '1' -> /handletype1"             "/handletype1 - Received message e2e00001"
wait_log "type '2' -> /handletype2"             "/handletype2 - Received message e2e00002"
wait_log "type '0' -> /dafault-messagehandler"  "/dafault-messagehandler - Received message e2e00003"
wait_log "type '99' -> /dafault-messagehandler" "/dafault-messagehandler - Received message e2e00005"
wait_log "bytes type '1' -> /handletype1"       "/handletype1 - Received message e2e00004"

echo ""
echo "--- Verifying OTel traces land in Jaeger (${JAEGER_POLL_SECONDS}s budget) ---"
assert_traces_delivering

echo ""
echo "--- Verifying 500 application/problem+json on publish failure (real Kestrel) ---"
assert_problem_json_on_publish_failure

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
