#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
ensure_context
validate_repo_config

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  fail "Python is required for secret serialization."
fi

if kubectl --context "$KUBE_CONTEXT" -n argocd \
  get secret kubeforge-github-repository >/dev/null 2>&1; then
  fail "Repository Secret already exists. Remove it manually before registering another credential."
fi

read -r -p "GitHub username: " GITHUB_USERNAME
read -r -s -p "GitHub read-only access token: " GITHUB_TOKEN
printf '\n'
[[ -n "$GITHUB_USERNAME" && -n "$GITHUB_TOKEN" ]] || fail "Username and token are required."
export GIT_REPO_URL GITHUB_USERNAME

log "Registering private GitHub repository..."
# Token goes through stdin, not process arguments or project files.
printf '%s' "$GITHUB_TOKEN" |
  "$PYTHON" -c '
import json, os, sys
token = sys.stdin.read()
print(json.dumps({
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": {
        "name": "kubeforge-github-repository",
        "namespace": "argocd",
        "labels": {"argocd.argoproj.io/secret-type": "repository"}
    },
    "type": "Opaque",
    "stringData": {
        "url": os.environ["GIT_REPO_URL"],
        "username": os.environ["GITHUB_USERNAME"],
        "password": token
    }
}))
' |
  kubectl --context "$KUBE_CONTEXT" create -f -
unset GITHUB_TOKEN
log "Repository credentials registered in Argo CD namespace."
