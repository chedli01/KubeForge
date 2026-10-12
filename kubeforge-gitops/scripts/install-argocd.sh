#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
ensure_context

ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

log "Creating argocd namespace if needed..."
kubectl --context "$KUBE_CONTEXT" create namespace argocd --dry-run=client -o yaml |
  kubectl --context "$KUBE_CONTEXT" apply -f -

log "Installing Argo CD ${ARGOCD_VERSION} from the official pinned manifest..."
# Server-side apply is necessary for large Argo CD CRDs.
kubectl --context "$KUBE_CONTEXT" -n argocd apply \
  --server-side --force-conflicts -f "$ARGOCD_INSTALL_URL"

log "Waiting for Argo CD controller..."
kubectl --context "$KUBE_CONTEXT" -n argocd rollout status \
  statefulset/argocd-application-controller --timeout=600s

log "Waiting for Argo CD API server and repository server..."
for deployment in argocd-server argocd-repo-server; do
  kubectl --context "$KUBE_CONTEXT" -n argocd rollout status \
    "deployment/$deployment" --timeout=600s
done

log "Argo CD Pods:"
kubectl --context "$KUBE_CONTEXT" -n argocd get pods
log "Argo CD installation complete."
