#!/usr/bin/env bash
# Shared paths, environment, and utilities for platform scripts.
# Independent of kubeforge-bootstrap so platform configuration can evolve separately.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/cluster.env
source "$PROJECT_ROOT/config/cluster.env"

log() { printf '\n[KubeForge Platform] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
require() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}
ensure_context() {
  require kubectl
  kubectl config get-contexts -o name | grep -Fxq "$KUBE_CONTEXT" || \
    fail "Kubernetes context '$KUBE_CONTEXT' not found. Bootstrap the kind cluster first."
  # Fail before writing anything if the control plane isn't reachable.
  kubectl --context "$KUBE_CONTEXT" get nodes -o name >/dev/null || \
  fail "Cannot access Kubernetes cluster using context '$KUBE_CONTEXT'."
}
ensure_crossplane() {
  kubectl --context "$KUBE_CONTEXT" -n crossplane-system \
    get deployment crossplane >/dev/null || \
    fail 'Crossplane is not installed. Run the bootstrap installation first.'
}
