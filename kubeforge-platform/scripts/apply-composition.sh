#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require kubectl
ensure_context
ensure_crossplane

log 'Granting Crossplane permission to manage Namespaces and ResourceQuotas...'
kubectl --context "$KUBE_CONTEXT" apply -f "$PROJECT_ROOT/manifests/rbac/crossplane-native-resources.yaml"

log 'Registering the DevEnvironment Composition...'
kubectl --context "$KUBE_CONTEXT" apply -f "$PROJECT_ROOT/manifests/compositions/dev-environment.yaml"
kubectl --context "$KUBE_CONTEXT" get composition kubeforge-devenvironment
log 'Composition registered.'
