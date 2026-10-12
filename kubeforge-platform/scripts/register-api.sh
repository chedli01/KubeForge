#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require kubectl
ensure_context
ensure_crossplane

log 'Registering the DevEnvironment XRD...'
kubectl --context "$KUBE_CONTEXT" apply -f "$PROJECT_ROOT/manifests/xrds/dev-environment.yaml"
kubectl --context "$KUBE_CONTEXT" wait --for=condition=Established \
  xrd/devenvironments.platform.kubeforge.io --timeout=180s
kubectl --context "$KUBE_CONTEXT" wait --for=condition=Established \
  crd/devenvironments.platform.kubeforge.io --timeout=180s
kubectl --context "$KUBE_CONTEXT" api-resources --api-group=platform.kubeforge.io
log 'DevEnvironment custom API is registered.'
