#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
ensure_context

log "Waiting for Argo CD Application to synchronize Git..."
if ! kubectl --context "$KUBE_CONTEXT" -n argocd wait \
  --for=jsonpath='{.status.sync.status}'=Synced \
  "application/$APP_NAME" --timeout=600s; then
  kubectl --context "$KUBE_CONTEXT" -n argocd describe application "$APP_NAME" || true
  fail "Argo CD Application did not reach Synced. Check Git repository, branch, path and credentials."
fi

log "Waiting for DevEnvironment XR to be created by Argo CD..."
kubectl --context "$KUBE_CONTEXT" wait \
  --for=create "devenvironment/$TEST_ENV" --timeout=300s

log "Waiting for Crossplane to reconcile the XR..."
kubectl --context "$KUBE_CONTEXT" wait \
  --for=condition=Ready "devenvironment/$TEST_ENV" --timeout=300s

log "Checking the created namespace and quota..."
kubectl --context "$KUBE_CONTEXT" get namespace "$TEST_ENV"
kubectl --context "$KUBE_CONTEXT" -n "$TEST_ENV" get resourcequota environment-quota

log "Argo CD Application:"
kubectl --context "$KUBE_CONTEXT" -n argocd get application "$APP_NAME"
log "GitOps provisioning verification passed."
