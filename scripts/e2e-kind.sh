#!/usr/bin/env bash
# K8s e2e: bring up KinD with Dapr + Kafka + producer/consumer, exercise
# the publish path through the LoadBalancer IP, and assert subscription
# routing via the consumer pod's stdout.
set -euo pipefail

CLUSTER="${KIND_CLUSTER_NAME:-dapr-pubsub}"
NS="${NAMESPACE:-dapr-pubsub}"
KUBECTL=(kubectl --context="kind-${CLUSTER}")
PROPAGATION_TIMEOUT="${PROPAGATION_TIMEOUT:-90}"
PASS=0
FAIL=0

if [[ ! -f /tmp/dapr-pubsub-producer-ip ]]; then
    echo "ERROR: /tmp/dapr-pubsub-producer-ip not found — run kind-up first"
    exit 1
fi
PRODUCER_URL="http://$(cat /tmp/dapr-pubsub-producer-ip)"

assert_status() {
    local method="$1" url="$2" expected="$3" body="${4:-}"
    local opts=(-s -o /dev/null -w '%{http_code}' -X "$method" --max-time 5)
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

# Poll the consumer pod's stdout via `kubectl logs` until the expected
# line appears or the timeout elapses.
wait_log() {
    local label="$1" pattern="$2"
    local deadline=$(( $(date +%s) + PROPAGATION_TIMEOUT ))
    while [[ $(date +%s) -lt $deadline ]]; do
        if "${KUBECTL[@]}" -n "$NS" logs -l app=consumer -c consumer --tail=-1 2>/dev/null \
            | grep -qF "$pattern"; then
            echo "PASS: consumer received '$label'"
            PASS=$((PASS + 1))
            return 0
        fi
        sleep 2
    done
    echo "FAIL: consumer never received '$label' within ${PROPAGATION_TIMEOUT}s"
    FAIL=$((FAIL + 1))
}

echo "=== K8s e2e against $PRODUCER_URL ==="
echo ""

echo "--- Smoke check ---"
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
echo "--- Verifying subscription routing (consumer pod stdout, ${PROPAGATION_TIMEOUT}s budget) ---"
wait_log "type '1' -> /handletype1"             "/handletype1 - Received message e2e00001"
wait_log "type '2' -> /handletype2"             "/handletype2 - Received message e2e00002"
wait_log "type '0' -> /dafault-messagehandler"  "/dafault-messagehandler - Received message e2e00003"
wait_log "type '99' -> /dafault-messagehandler" "/dafault-messagehandler - Received message e2e00005"
wait_log "bytes type '1' -> /handletype1"       "/handletype1 - Received message e2e00004"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
