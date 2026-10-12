#!/usr/bin/env bash
# Shared initialization for GitOps scripts, independent of kubeforge-bootstrap.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/gitops.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Missing $CONFIG_FILE" >&2
  echo "Run: cp config/gitops.env.example config/gitops.env" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

log() { printf '\n[KubeForge GitOps] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || fail "Command not found: $1"; }

ensure_context() {
  require kubectl
  # kubectl get --raw=/readyz suffers Git Bash path conversion on Windows.
  kubectl --context "$KUBE_CONTEXT" get nodes -o name >/dev/null ||
    fail "Cannot access Kubernetes context: $KUBE_CONTEXT"
}

validate_repo_config() {
  [[ "$GIT_REPO_URL" == https://github.com/* ]] ||
    fail "GIT_REPO_URL must be a GitHub HTTPS repository URL."
  [[ "$GIT_REPO_URL" != *YOUR_USER* && "$GIT_REPO_URL" != *YOUR_REPOSITORY* ]] ||
    fail "Replace the GitHub repository placeholders in config/gitops.env."
  [[ "$GIT_REPO_URL" != *'|'* && "$GIT_REPO_URL" != *'&'* && "$GIT_REPO_URL" != *'\'* ]] ||
    fail "Unsupported character in GitHub repository URL."
  [[ "$GIT_REVISION" =~ ^[a-zA-Z0-9._/-]+$ ]] || fail "Invalid Git revision."
  [[ "$GIT_PATH" =~ ^[a-zA-Z0-9._/-]+$ && "$GIT_PATH" != /* && "$GIT_PATH" != *..* ]] ||
    fail "Invalid repository path."
  [[ "$APP_NAME" =~ ^[a-z0-9-]+$ ]] || fail "Invalid application name."
}
