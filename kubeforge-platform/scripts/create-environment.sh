#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require kubectl
ensure_context

log 'Creating DevEnvironment/payments-dev directly with kubectl...'
kubectl --context "$KUBE_CONTEXT" apply -f "$PROJECT_ROOT/examples/payments-dev.yaml"
kubectl --context "$KUBE_CONTEXT" get devenvironments.platform.kubeforge.io
