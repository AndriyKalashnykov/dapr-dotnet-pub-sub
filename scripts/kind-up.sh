#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Bootstrap a KinD cluster for the K8s e2e: creates the cluster, starts
# cloud-provider-kind (so Services of type LoadBalancer get external IPs),
# installs Dapr via Helm and Kafka via the Bitnami chart, loads the
# producer/consumer images, and applies the manifests in k8s/.
set -euo pipefail

CLUSTER="${KIND_CLUSTER_NAME:-dapr-pubsub}"
NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.34.0}"
DAPR_HELM_VERSION="${DAPR_HELM_VERSION:-1.17.4}"
NS="${NAMESPACE:-dapr-pubsub}"
KUBECTL=(kubectl --context="kind-${CLUSTER}")
HELM=(helm --kube-context="kind-${CLUSTER}")

if ! kind get clusters 2>/dev/null | grep -qE "^${CLUSTER}$"; then
    echo "=== Creating KinD cluster ${CLUSTER} (${NODE_IMAGE}) ==="
    kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --wait 120s
else
    echo "KinD cluster ${CLUSTER} already exists."
    kubectl config use-context "kind-${CLUSTER}"
fi

# cloud-provider-kind runs on the host as a daemon, watching kind clusters
# and reconciling Service of type LoadBalancer to per-Service Envoy sidecars
# inside the kind Docker network.
if ! pgrep -f 'cloud-provider-kind' >/dev/null 2>&1; then
    echo "=== Starting cloud-provider-kind (host binary, backgrounded) ==="
    nohup cloud-provider-kind >/tmp/cloud-provider-kind.log 2>&1 &
    sleep 3
fi

echo "=== Loading producer + consumer images into KinD ==="
kind load docker-image --name "$CLUSTER" \
    dapr-dotnet-pub-sub-producer:e2e \
    dapr-dotnet-pub-sub-consumer:e2e

echo "=== Installing Dapr (Helm ${DAPR_HELM_VERSION}) ==="
"${HELM[@]}" repo add dapr https://dapr.github.io/helm-charts/ >/dev/null 2>&1 || true
"${HELM[@]}" repo update dapr >/dev/null
"${HELM[@]}" upgrade --install dapr dapr/dapr \
    --version "$DAPR_HELM_VERSION" \
    --namespace dapr-system \
    --create-namespace \
    --set global.ha.enabled=false \
    --set global.mtls.enabled=false \
    --wait --timeout 180s

echo "=== Creating namespace ${NS} ==="
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/namespace.yaml"

echo "=== Deploying Jaeger (all-in-one) ==="
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/jaeger.yaml"
"${KUBECTL[@]}" -n "$NS" rollout status deployment/jaeger --timeout=120s

echo "=== Deploying Kafka (KRaft StatefulSet) ==="
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/kafka.yaml"
"${KUBECTL[@]}" -n "$NS" rollout status statefulset/kafka --timeout=240s

echo "=== Applying Dapr Configuration + Component + Subscription + apps ==="
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/config.yaml"
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/pubsub.yaml"
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/subscription.yaml"
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/producer.yaml"
"${KUBECTL[@]}" apply -f "$(dirname "$0")/../k8s/consumer.yaml"

echo "=== Waiting for deployments ==="
"${KUBECTL[@]}" -n "$NS" rollout status deployment/producer --timeout=180s
"${KUBECTL[@]}" -n "$NS" rollout status deployment/consumer --timeout=180s

echo "=== Waiting for LoadBalancer IP on producer ==="
for _ in $(seq 1 60); do
    IP=$("${KUBECTL[@]}" -n "$NS" get svc producer \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [[ -n "$IP" ]]; then
        echo "Producer LoadBalancer IP: $IP"
        break
    fi
    sleep 2
done
if [[ -z "${IP:-}" ]]; then
    echo "ERROR: LoadBalancer IP was not assigned within timeout"
    exit 1
fi

# Route readiness — cloud-provider-kind's per-Service Envoy sidecar can take
# 5-60s after IP assignment to actually route the data path.
echo "=== Polling route readiness on http://${IP}/dapr/config ==="
for _ in $(seq 1 60); do
    if curl -sf -o /dev/null --max-time 2 "http://${IP}/dapr/config"; then
        echo "Producer route is live."
        echo "$IP" > /tmp/dapr-pubsub-producer-ip
        exit 0
    fi
    sleep 2
done
echo "ERROR: producer route never became reachable at http://${IP}/dapr/config"
"${KUBECTL[@]}" -n "$NS" get pods,svc
"${KUBECTL[@]}" -n "$NS" describe svc producer || true
exit 1
