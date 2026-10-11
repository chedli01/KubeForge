#!/usr/bin/env bash
# Shared configuration for all bootstrap scripts. Always source this file.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/versions.env
source "$PROJECT_ROOT/config/versions.env"
KIND_CONTEXT="kind-${KIND_CLUSTER_NAME}"
LOCAL_BIN="$PROJECT_ROOT/.tools/bin"
export PATH="$LOCAL_BIN:$PATH"

log() { printf '\n[KubeForge] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}
ensure_context() {
  require kubectl
  kubectl config get-contexts -o name | grep -Fxq "$KIND_CONTEXT" || \
    fail "Kubernetes context '$KIND_CONTEXT' is missing. Run 01-create-cluster.sh first."
}
