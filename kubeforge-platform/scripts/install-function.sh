#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require kubectl
ensure_context
ensure_crossplane

log 'Installing the pinned Go-templating Composition Function...'
kubectl --context "$KUBE_CONTEXT" apply -f "$PROJECT_ROOT/manifests/functions/go-templating.yaml"
kubectl --context "$KUBE_CONTEXT" wait \
  --for=condition=Installed function.pkg.crossplane.io/function-go-templating --timeout=300s
kubectl --context "$KUBE_CONTEXT" wait \
  --for=condition=Healthy function.pkg.crossplane.io/function-go-templating --timeout=300s
kubectl --context "$KUBE_CONTEXT" get functions.pkg.crossplane.io
log 'Composition Function installed and healthy.'
