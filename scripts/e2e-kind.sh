#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# K8s e2e: bring up KinD with Dapr + Kafka + producer/consumer, exercise
# the publish path through the LoadBalancer IP, and assert subscription
# routing via the consumer pod's stdout.
set -euo pipefail

CLUSTER="${KIND_CLUSTER_NAME:-dapr-pubsub}"
NS="${NAMESPACE:-dapr-pubsub}"
KUBECTL=(kubectl --context="kind-${CLUSTER}")
PROPAGATION_TIMEOUT="${PROPAGATION_TIMEOUT:-90}"
CURL_MAX_TIME="${CURL_MAX_TIME:-5}"
JAEGER_POLL_SECONDS="${JAEGER_POLL_SECONDS:-60}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"
OTEL_PRODUCER_SERVICE="${OTEL_PRODUCER_SERVICE:-producer}"
PASS=0
FAIL=0

# Ephemeral local ports for kubectl port-forward aliases (kernel-allocated,
# race-free, parallel-safe — never a fixed literal).
pick_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()'; }

PF_PIDS=()
cleanup_pf() {
    for pid in "${PF_PIDS[@]:-}"; do
        if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    done
    PF_PIDS=()
}
trap cleanup_pf EXIT

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

# Two-stage OTel check (see e2e-compose.sh for the rationale): assert the
# producer service is registered AND a trace was recorded during THIS run.
# With app-side OpenTelemetry the producer's own /send HTTP handler is traced,
# so driving the real publish endpoint (via the LoadBalancer) generates the
# span. Jaeger's query API is reached via a kernel-ephemeral-port port-forward.
assert_traces_delivering() {
    local jaeger_port
    jaeger_port=$(pick_port)
    "${KUBECTL[@]}" -n "$NS" port-forward svc/jaeger "${jaeger_port}:16686" >/dev/null 2>&1 &
    PF_PIDS+=($!)

    # Wait for the Jaeger query port-forward to accept (proves the data path).
    local ready=""
    for _ in $(seq 1 30); do
        if curl -sf -o /dev/null --max-time 2 "http://localhost:${jaeger_port}/api/services" 2>/dev/null; then
            ready=yes; break
        fi
        sleep 1
    done
    if [[ "$ready" != yes ]]; then
        echo "FAIL: Jaeger query port-forward never became ready"
        FAIL=$((FAIL + 1)); return
    fi

    for _ in 1 2 3 4 5; do
        curl -s -o /dev/null --max-time "$CURL_MAX_TIME" -X POST "$PRODUCER_URL/send" \
            -H 'Content-Type: application/json' \
            -d '{"id":"trace001-0000-0000-0000-000000000001","timeStamp":"2025-09-26T02:52:04.835Z","type":"1"}' || true
    done

    local deadline=$(( $(date +%s) + JAEGER_POLL_SECONDS ))
    local seen_svc="" seen_trace=""
    while [[ $(date +%s) -lt $deadline ]]; do
        if [[ "$seen_svc" != yes ]] && curl -sf --max-time "$CURL_MAX_TIME" \
                "http://localhost:${jaeger_port}/api/services" 2>/dev/null | grep -q "\"$OTEL_PRODUCER_SERVICE\""; then
            seen_svc=yes
        fi
        if [[ "$seen_svc" == yes && "$seen_trace" != yes ]] && curl -sf --max-time "$CURL_MAX_TIME" \
                "http://localhost:${jaeger_port}/api/traces?service=$OTEL_PRODUCER_SERVICE&limit=1" 2>/dev/null | grep -q '"traceID"'; then
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
neg_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$CURL_MAX_TIME" \
    -X POST "$PRODUCER_URL/send" -H 'Content-Type: text/plain' -d 'not json')
if [[ "$neg_status" == 415 ]]; then
    echo "PASS: POST /send text/plain -> 415"; PASS=$((PASS + 1))
else
    echo "FAIL: POST /send text/plain -> $neg_status (expected 415)"; FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Verifying subscription routing (consumer pod stdout, ${PROPAGATION_TIMEOUT}s budget) ---"
wait_log "type '1' -> /handletype1"             "/handletype1 - Received message e2e00001"
wait_log "type '2' -> /handletype2"             "/handletype2 - Received message e2e00002"
wait_log "type '0' -> /dafault-messagehandler"  "/dafault-messagehandler - Received message e2e00003"
wait_log "type '99' -> /dafault-messagehandler" "/dafault-messagehandler - Received message e2e00005"
wait_log "bytes type '1' -> /handletype1"       "/handletype1 - Received message e2e00004"

echo ""
echo "--- Verifying OTel traces land in Jaeger (${JAEGER_POLL_SECONDS}s budget) ---"
assert_traces_delivering

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
