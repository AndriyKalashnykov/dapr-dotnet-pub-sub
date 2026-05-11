#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tear down the KinD cluster + cloud-provider-kind. Also prunes any
# orphan kindccm-* envoy sidecars (cloud-provider-kind's per-Service
# proxy containers that survive cluster deletion and would otherwise
# hold IPs in the kind Docker subnet on the next bring-up).
set -euo pipefail

CLUSTER="${KIND_CLUSTER_NAME:-dapr-pubsub}"

echo "=== Stopping cloud-provider-kind controller ==="
pkill -f 'cloud-provider-kind' 2>/dev/null || true

echo "=== Pruning kindccm-* orphan sidecars ==="
docker ps -aq --filter name=kindccm- | xargs -r docker rm -f >/dev/null 2>&1 || true

if kind get clusters 2>/dev/null | grep -qE "^${CLUSTER}$"; then
    echo "=== Deleting KinD cluster ${CLUSTER} ==="
    kind delete cluster --name "$CLUSTER"
else
    echo "KinD cluster ${CLUSTER} not found — nothing to delete."
fi
