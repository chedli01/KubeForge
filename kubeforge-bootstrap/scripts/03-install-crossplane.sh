#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require helm
ensure_context

log "Adding official Crossplane stable Helm chart repository..."
helm repo add crossplane-stable https://charts.crossplane.io/stable --force-update
helm repo update crossplane-stable

log "Installing Crossplane chart version $CROSSPLANE_VERSION into '$KIND_CONTEXT'..."
helm upgrade --install crossplane crossplane-stable/crossplane \
  --version "$CROSSPLANE_VERSION" \
  --namespace crossplane-system \
  --create-namespace \
  --kube-context "$KIND_CONTEXT" \
  --wait \
  --timeout 10m

log 'Checking both Crossplane controller deployments...'
kubectl --context "$KIND_CONTEXT" -n crossplane-system rollout status \
  deployment/crossplane --timeout=300s
kubectl --context "$KIND_CONTEXT" -n crossplane-system rollout status \
  deployment/crossplane-rbac-manager --timeout=300s
kubectl --context "$KIND_CONTEXT" get pods -n crossplane-system
log 'Crossplane core is installed (XRDs/Compositions come in the next phase).'
