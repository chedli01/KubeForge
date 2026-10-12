#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require kubectl
ensure_context

log 'Waiting for Namespace and ResourceQuota created by Crossplane...'
kubectl --context "$KUBE_CONTEXT" wait --for=create namespace/payments-dev --timeout=180s
kubectl --context "$KUBE_CONTEXT" wait --for=create \
  resourcequota/environment-quota --namespace payments-dev --timeout=180s

log 'Waiting for the DevEnvironment Ready condition...'
kubectl --context "$KUBE_CONTEXT" wait --for=condition=Ready \
  devenvironment.platform.kubeforge.io/payments-dev --timeout=180s

cpu="$(kubectl --context "$KUBE_CONTEXT" -n payments-dev get resourcequota environment-quota -o go-template='{{index .spec.hard "requests.cpu"}}')"
mem="$(kubectl --context "$KUBE_CONTEXT" -n payments-dev get resourcequota environment-quota -o go-template='{{index .spec.hard "requests.memory"}}')"
[[ "$cpu" == '2' && "$mem" == '4Gi' ]] || fail "Unexpected quota: cpu=$cpu memory=$mem"

kubectl --context "$KUBE_CONTEXT" get devenvironments.platform.kubeforge.io
kubectl --context "$KUBE_CONTEXT" get namespace payments-dev --show-labels
kubectl --context "$KUBE_CONTEXT" -n payments-dev describe resourcequota environment-quota
log 'SUCCESS: Namespace/payments-dev and ResourceQuota/environment-quota (2 CPU, 4Gi memory).'
