#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
ensure_context
log "Dashboard URL: https://localhost:8080"
log "Default username: admin"
log "Initial password (only while the initial secret exists):"
if kubectl --context "$KUBE_CONTEXT" -n argocd \
   get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  kubectl --context "$KUBE_CONTEXT" -n argocd \
    get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  printf '\n'
else
  log "Initial password secret unavailable; use your existing credentials."
fi
log "Starting local port-forward. Press Ctrl+C to exit."
kubectl --context "$KUBE_CONTEXT" -n argocd port-forward svc/argocd-server 8080:443
