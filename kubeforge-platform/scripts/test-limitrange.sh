#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"

ensure_context

# Default test target: existing small environment.
ENV_NAME="${1:-payments-dev}"

log "Checking LimitRange in namespace '$ENV_NAME'..."

kubectl --context "$KUBE_CONTEXT" -n "$ENV_NAME" \
  get limitrange environment-limits >/dev/null ||
  fail "LimitRange environment-limits is missing."

XR_SIZE="$(kubectl --context "$KUBE_CONTEXT" \
  get devenvironment "$ENV_NAME" \
  -o jsonpath='{.spec.size}')"

[[ "$XR_SIZE" == "small" ]] ||
  fail "This test expects size=small; got size=$XR_SIZE."


# ------------------------------------------------
# TEST 1: Automatic default injection
# ------------------------------------------------

log "TEST 1: Checking automatic resource defaults..."

ACTUAL="$(kubectl --context "$KUBE_CONTEXT" -n "$ENV_NAME" \
  create --dry-run=server -f - \
  -o jsonpath='{.spec.containers[0].resources.requests.cpu}{"|"}{.spec.containers[0].resources.requests.memory}{"|"}{.spec.containers[0].resources.limits.cpu}{"|"}{.spec.containers[0].resources.limits.memory}' <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: kubeforge-limitrange-default-test
spec:
  containers:
    - name: test
      image: nginx:alpine
YAML
)" || fail "Server-side dry run failed."

EXPECTED="100m|128Mi|500m|512Mi"

[[ "$ACTUAL" == "$EXPECTED" ]] ||
  fail "Incorrect defaults. Expected '$EXPECTED', got '$ACTUAL'."

log "PASS: Kubernetes injected the expected defaults."


# ------------------------------------------------
# TEST 2: Maximum CPU limit enforcement
# ------------------------------------------------

log "TEST 2: Checking maximum CPU limit enforcement..."

if ERROR="$(kubectl --context "$KUBE_CONTEXT" -n "$ENV_NAME" \
  create --dry-run=server -f - 2>&1 <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: kubeforge-limitrange-maximum-test
spec:
  containers:
    - name: test
      image: nginx:alpine
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: "2"
          memory: 512Mi
YAML
)"; then
  fail "Kubernetes accepted CPU limit=2, but max=1."
fi

# Ensure rejection was caused by the CPU maximum rule.
if ! grep -Eqi '(maximum.*cpu|cpu.*maximum)' <<< "$ERROR"; then
  fail "Unexpected rejection reason: $ERROR"
fi

log "PASS: Kubernetes rejected CPU limit=2 (max=1)."

log "SUCCESS: All LimitRange enforcement tests passed."
log "No Pods were created."
