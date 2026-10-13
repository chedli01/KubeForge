
#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"

ensure_context

ENV_NAME="${1:-payments-dev}"
SA_NAME="environment-deployer"
IDENTITY="system:serviceaccount:${ENV_NAME}:${SA_NAME}"

# ---------------------------------------------
# TEST 1: Verify RBAC resource provisioning
# ---------------------------------------------

log "Checking RBAC provisioning in '${ENV_NAME}'..."

kubectl --context "$KUBE_CONTEXT" \
  get devenvironment "$ENV_NAME" >/dev/null ||
  fail "DevEnvironment '$ENV_NAME' not found."

for resource in \
  role/environment-viewer \
  role/environment-deployer \
  serviceaccount/environment-deployer \
  rolebinding/environment-deployer; do

  kubectl --context "$KUBE_CONTEXT" -n "$ENV_NAME" \
    get "$resource" >/dev/null ||
    fail "Missing: $resource"

  log "PASS: $resource exists."
done

# ---------------------------------------------
# TEST 2: Verify RoleBinding configuration
# ---------------------------------------------

BINDING="$(kubectl --context "$KUBE_CONTEXT" -n "$ENV_NAME" \
  get rolebinding environment-deployer \
  -o jsonpath='{.roleRef.kind}{"|"}{.roleRef.name}{"|"}{.subjects[0].kind}{"|"}{.subjects[0].name}{"|"}{.subjects[0].namespace}')"

EXPECTED_BINDING="Role|environment-deployer|ServiceAccount|environment-deployer|${ENV_NAME}"

[[ "$BINDING" == "$EXPECTED_BINDING" ]] ||
  fail "Unexpected RoleBinding. Expected '$EXPECTED_BINDING'; got '$BINDING'."

log "PASS: RoleBinding correctly binds the deployer Role to its ServiceAccount."

# ---------------------------------------------
# TEST 3: Verify Kubernetes RBAC enforcement
# ---------------------------------------------

assert_permission() {
  local expected="$1" verb="$2" resource="$3" result

  if result="$(kubectl --context "$KUBE_CONTEXT" auth can-i \
    "$verb" "$resource" -n "$ENV_NAME" \
    --as="$IDENTITY" 2>&1)"; then
    :
  else
    # A legitimate "no" produces a nonzero exit code.
    [[ "$result" == "no" ]] ||
      fail "Authorization check failed: $result"
  fi

  [[ "$result" == "$expected" ]] ||
    fail "Expected '$expected' for '$verb $resource'; got '$result'."

  log "PASS: $verb $resource -> $result (expected $expected)."
}

log "Testing RBAC permissions as '${IDENTITY}'..."

# Allowed: deployment creation.
assert_permission yes create deployments.apps

# Forbidden: modifying resource quotas.
assert_permission no delete resourcequotas

# Forbidden: creating new RBAC bindings.
assert_permission no create rolebindings

log "SUCCESS: RBAC resources and authorization checks passed."
log "No workloads or permissions were changed."
