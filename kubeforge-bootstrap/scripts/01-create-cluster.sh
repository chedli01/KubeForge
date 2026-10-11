#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require kind
require kubectl
require docker

docker info >/dev/null 2>&1 || fail 'Start Docker Desktop before creating the cluster.'

if kind get clusters | grep -Fxq "$KIND_CLUSTER_NAME"; then
  log "Cluster '$KIND_CLUSTER_NAME' already exists; leaving it unchanged."
else
  log "Creating '$KIND_CLUSTER_NAME' with 1 control plane and 3 workers..."
  kind create cluster \
    --name "$KIND_CLUSTER_NAME" \
    --config "$PROJECT_ROOT/config/kind-cluster.yaml" \
    --image "$KIND_NODE_IMAGE" \
    --wait 5m
fi

ensure_context
log 'Waiting for Kubernetes nodes to become Ready...'
kubectl --context "$KIND_CONTEXT" wait \
  --for=condition=Ready nodes --all --timeout=240s
kubectl --context "$KIND_CONTEXT" get nodes -o wide

NODE_COUNT="$(kubectl --context "$KIND_CONTEXT" get nodes -o name | wc -l | tr -d '[:space:]')"
[[ "$NODE_COUNT" == 4 ]] || fail "Expected 4 nodes, found $NODE_COUNT."
log 'Success: 1 control-plane node + 3 workers are ready.'
