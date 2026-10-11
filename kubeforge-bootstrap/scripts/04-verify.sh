#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require helm
ensure_context

log 'Checking cluster and installed versions...'
kind --version
helm version --short
kubectl --context "$KIND_CONTEXT" get nodes -o wide
kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready nodes --all --timeout=120s

NODE_COUNT="$(kubectl --context "$KIND_CONTEXT" get nodes -o name | wc -l | tr -d '[:space:]')"
[[ "$NODE_COUNT" == 4 ]] || fail "Expected 4 nodes, found $NODE_COUNT."

log 'Checking Crossplane Helm release...'
helm status crossplane -n crossplane-system --kube-context "$KIND_CONTEXT"

log 'Checking Crossplane controllers and API types...'
kubectl --context "$KIND_CONTEXT" -n crossplane-system rollout status deployment/crossplane --timeout=120s
kubectl --context "$KIND_CONTEXT" -n crossplane-system rollout status deployment/crossplane-rbac-manager --timeout=120s
kubectl --context "$KIND_CONTEXT" get crd compositeresourcedefinitions.apiextensions.crossplane.io

log 'SUCCESS: 4-node kind cluster, Helm, and Crossplane are ready.'
