#!/usr/bin/env bash
# Real-sidecar e2e test: exercises the full Producer -> Kafka -> Consumer
# pipeline through the Dapr sidecar. Requires Kafka and Dapr apps to be
# running (the Makefile e2e-sidecar target handles lifecycle).
set -euo pipefail

PRODUCER_URL="http://localhost:5232"
DAPR_LOG="${DAPR_LOG:?DAPR_LOG env var must point to the dapr run log file}"
PASS=0
FAIL=0

assert_status() {
    local method="$1" url="$2" expected="$3" body="${4:-}"
    local opts=(-s -o /dev/null -w '%{http_code}' -X "$method")
    [[ -n "$body" ]] && opts+=(-H 'Content-Type: application/json' -d "$body")
    local status
    status=$(curl "${opts[@]}" "$url")
    if [[ "$status" == "$expected" ]]; then
        echo "PASS: $method $url -> $status"
        ((PASS++))
    else
        echo "FAIL: $method $url -> $status (expected $expected)"
        ((FAIL++))
    fi
}

assert_log_contains() {
    local label="$1" pattern="$2"
    if grep -q "$pattern" "$DAPR_LOG"; then
        echo "PASS: log contains '$label'"
        ((PASS++))
    else
        echo "FAIL: log missing '$label'"
        ((FAIL++))
    fi
}

echo "=== E2E Sidecar Tests against $PRODUCER_URL ==="
echo ""

# --- Publish messages through the real Dapr sidecar ---
echo "--- Publishing messages via /send ---"

assert_status POST "$PRODUCER_URL/send" 202 \
    '{"id":"e2e00001-0000-0000-0000-000000000001","timeStamp":"2025-09-26T02:52:04.835Z","type":"1"}'

assert_status POST "$PRODUCER_URL/send" 202 \
    '{"id":"e2e00002-0000-0000-0000-000000000002","timeStamp":"2025-09-26T02:52:04.835Z","type":"2"}'

assert_status POST "$PRODUCER_URL/send" 202 \
    '{"id":"e2e00003-0000-0000-0000-000000000003","timeStamp":"2025-09-26T02:52:04.835Z","type":"0"}'

echo ""
echo "--- Publishing messages via /sendasbytes ---"

assert_status POST "$PRODUCER_URL/sendasbytes" 202 \
    '{"id":"e2e00004-0000-0000-0000-000000000004","timeStamp":"2025-09-27T02:52:04.835Z","type":"1"}'

echo ""
echo "--- Negative cases ---"

assert_status POST "$PRODUCER_URL/send" 400 '{not-json}'

# --- Wait for Kafka propagation + Dapr subscription delivery ---
echo ""
echo "Waiting 15s for Kafka message propagation..."
sleep 15

# --- Verify consumer received messages via Dapr log ---
echo ""
echo "--- Verifying consumer received messages (subscription routing) ---"

assert_log_contains \
    "type '1' routed to /handletype1" \
    "/handletype1 - Received message e2e00001"

assert_log_contains \
    "type '2' routed to /handletype2" \
    "/handletype2 - Received message e2e00002"

assert_log_contains \
    "type '0' routed to /dafault-messagehandler" \
    "/dafault-messagehandler - Received message e2e00003"

assert_log_contains \
    "bytes type '1' routed to /handletype1" \
    "/handletype1 - Received message e2e00004"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
