#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Compose-based e2e: brings producer + consumer + Dapr sidecars + Kafka up
# via `docker compose --wait`, exercises pub/sub through real Dapr sidecars,
# and asserts subscription routing via the consumer container's stdout.
#
# Replaces the older e2e-sidecar.sh flow (background `dapr run -f .` + log
# file grep), which depended on the local Dapr CLI lifecycle.
set -euo pipefail

PRODUCER_URL="${PRODUCER_URL:-http://localhost:5232}"
COMPOSE_DIR="${COMPOSE_DIR:-$(dirname "$0")/../compose}"
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

echo ""
echo "--- Verifying subscription routing (consumer stdout, ${PROPAGATION_TIMEOUT}s budget) ---"
wait_log "type '1' -> /handletype1"             "/handletype1 - Received message e2e00001"
wait_log "type '2' -> /handletype2"             "/handletype2 - Received message e2e00002"
wait_log "type '0' -> /dafault-messagehandler"  "/dafault-messagehandler - Received message e2e00003"
wait_log "type '99' -> /dafault-messagehandler" "/dafault-messagehandler - Received message e2e00005"
wait_log "bytes type '1' -> /handletype1"       "/handletype1 - Received message e2e00004"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
