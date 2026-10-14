#!/usr/bin/env bash
# KubeForge - Crossplane DevEnvironment end-to-end tests
#
# Objective: verify the full Kubernetes lifecycle of a temporary DevEnvironment:
# creation -> composed resources -> API defaults -> admission/RBAC -> updates
# -> drift correction -> deletion.
#
# Requirements: kubectl, access to an initialized KubeForge cluster, Bash.
# Does NOT push to Git, modify ArgoCD, create running Pods, or test CNI enforcement.
# Usage (from kubeforge-platform/): bash tests/e2e/run-e2e.sh
# Optional: KUBE_CONTEXT=kind-kubeforge WAIT_TIMEOUT=240 bash tests/e2e/run-e2e.sh

set -Eeuo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-kind-kubeforge}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-240}"
INTERVAL=3
XR_NAME="e2e-$(date +%s)-${RANDOM}"
NAMESPACE="$XR_NAME"
TEAM="e2e"
DEPLOYER_ID="system:serviceaccount:${NAMESPACE}:environment-deployer"
CREATED_XR=false

log()  { printf '\n[KubeForge E2E] %s\n' "$*"; }
pass() { printf '[KubeForge E2E] PASS: %s\n' "$*"; }
fail() { printf '\n[KubeForge E2E] FAIL: %s\n' "$*" >&2; exit 1; }

# Wait until a predicate command succeeds, with a bounded timeout.
# Each predicate returns success (0) only when the expected state is observed.
wait_for() {
  local description="$1"; shift
  local start=$SECONDS
  until "$@"; do
    if (( SECONDS - start >= WAIT_TIMEOUT )); then
      fail "Timed out after ${WAIT_TIMEOUT}s: ${description}"
    fi
    sleep "$INTERVAL"
  done
  pass "$description"
}

# Get one field from a namespaced Kubernetes resource and compare it with
# the expected value. Missing resources/fields are treated as 'not ready yet'.
field_is() {
  local kind="$1" object="$2" path="$3" expected="$4" actual
  actual="$(kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
    get "$kind" "$object" -o "jsonpath=${path}" 2>/dev/null)" || return 1
  [[ "$actual" == "$expected" ]]
}

# Check an XR field (DevEnvironment XRs are cluster scoped).
xr_field_is() {
  local path="$1" expected="$2" actual
  actual="$(kubectl --context "$KUBE_CONTEXT" get devenvironment "$XR_NAME" \
    -o "jsonpath=${path}" 2>/dev/null)" || return 1
  [[ "$actual" == "$expected" ]]
}

# Check resource existence, used to verify all eight composed resources.
exists() {
  kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
    get "$1" "$2" >/dev/null 2>&1
}

namespace_exists() {
  kubectl --context "$KUBE_CONTEXT" get namespace "$NAMESPACE" >/dev/null 2>&1
}

namespace_absent() { ! namespace_exists; }
xr_absent() {
  ! kubectl --context "$KUBE_CONTEXT" get devenvironment "$XR_NAME" >/dev/null 2>&1
}

# Kubernetes 'auth can-i' returns text 'yes' or 'no'. We inspect that
# explicitly rather than relying only on its shell exit code.
permission_is() {
  local expected="$1" verb="$2" resource="$3" actual
  actual="$(kubectl --context "$KUBE_CONTEXT" auth can-i "$verb" "$resource" \
    -n "$NAMESPACE" --as="$DEPLOYER_ID" 2>/dev/null)" || {
      [[ "$actual" == "no" ]] || return 1
    }
  [[ "$actual" == "$expected" ]]
}

# On any exit (even after a failed assertion), request removal of ONLY the
# temporary XR created by this script. Crossplane owns cleanup of the Namespace
# and the other composed resources; never forcibly delete unrelated resources.
cleanup() {
  local result=$?
  trap - EXIT INT TERM
  if [[ "$CREATED_XR" == true ]]; then
    log "Cleanup: ensuring temporary DevEnvironment ${XR_NAME} is deleted..."
    kubectl --context "$KUBE_CONTEXT" delete devenvironment "$XR_NAME" \
      --ignore-not-found --wait=false >/dev/null 2>&1 || true
    if ! kubectl --context "$KUBE_CONTEXT" wait \
      --for=delete "namespace/${NAMESPACE}" --timeout=180s >/dev/null 2>&1; then
      if namespace_exists; then
        printf '[KubeForge E2E] WARNING: Namespace %s remains; inspect Crossplane reconciliation.\n' \
          "$NAMESPACE" >&2
      fi
    fi
  fi
  if (( result == 0 )); then
    log "All Crossplane lifecycle E2E tests passed."
  else
    log "E2E test failed (exit ${result}); temporary environment cleanup attempted."
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# -----------------------------------------------------------------------------
# STEP 1 - Prerequisites / safety checks.
# Confirm kubectl can reach the intended cluster and the DevEnvironment API and
# Composition already exist. Abort before creating anything if they do not.
# -----------------------------------------------------------------------------
log "STEP 1: Checking cluster prerequisites (context: ${KUBE_CONTEXT})..."
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed or not in PATH."
[[ "$WAIT_TIMEOUT" =~ ^[0-9]+$ ]] || fail "WAIT_TIMEOUT must be an integer (seconds)."
# Verify the Kubernetes API Server is accessible using the configured context.
# Avoid --raw=/readyz because Git Bash may convert the path on Windows.
kubectl --context "$KUBE_CONTEXT" get namespace kube-system >/dev/null 2>&1 || \
  fail "Cannot access the Kubernetes cluster using context ${KUBE_CONTEXT}."
kubectl --context "$KUBE_CONTEXT" get \
  compositeresourcedefinition devenvironments.platform.kubeforge.io >/dev/null 2>&1 || \
  fail "KubeForge DevEnvironment XRD is missing."
kubectl --context "$KUBE_CONTEXT" get \
  composition kubeforge-devenvironment >/dev/null 2>&1 || \
  fail "KubeForge Composition is missing."
kubectl --context "$KUBE_CONTEXT" get \
  function function-go-templating >/dev/null 2>&1 || \
  fail "Go-templating Composition Function is missing."
if ! xr_absent || namespace_exists; then
  fail "Generated test name ${XR_NAME} already exists; aborting to avoid modifying it."
fi
pass "KubeForge API, Composition and Function are installed."
log "Temporary environment: ${XR_NAME}"

# -----------------------------------------------------------------------------
# STEP 2 - Create a new DevEnvironment XR.
# Use size=small and omit networkProfile intentionally, to verify the XRD's
# secure default (isolated) and Crossplane's initial provisioning.
# -----------------------------------------------------------------------------
log "STEP 2: Creating temporary DevEnvironment (small, default network profile)..."
CREATED_XR=true
kubectl --context "$KUBE_CONTEXT" apply -f - <<YAML
apiVersion: platform.kubeforge.io/v1alpha1
kind: DevEnvironment
metadata:
  name: ${XR_NAME}
spec:
  team: ${TEAM}
  size: small
YAML
wait_for "Namespace created" namespace_exists

# -----------------------------------------------------------------------------
# STEP 3 - Verify all eight composed Kubernetes resources exist.
# Assert that the Composition created the quota, limits, RBAC identities/rules,
# and network policy along with the Namespace.
# -----------------------------------------------------------------------------
log "STEP 3: Verifying all 8 Crossplane-composed Kubernetes resources..."
wait_for "ResourceQuota/environment-quota exists" exists resourcequota environment-quota
wait_for "LimitRange/environment-limits exists" exists limitrange environment-limits
wait_for "Role/environment-viewer exists" exists role environment-viewer
wait_for "Role/environment-deployer exists" exists role environment-deployer
wait_for "ServiceAccount/environment-deployer exists" exists serviceaccount environment-deployer
wait_for "RoleBinding/environment-deployer exists" exists rolebinding environment-deployer
wait_for "NetworkPolicy/environment-network-policy exists" exists networkpolicy environment-network-policy
wait_for "XR is Synced" xr_field_is '{.status.conditions[?(@.type=="Synced")].status}' True
wait_for "XR is Ready" xr_field_is '{.status.conditions[?(@.type=="Ready")].status}' True
wait_for "Namespace has expected team label" field_is namespace "$NAMESPACE" \
  '{.metadata.labels.platform\.kubeforge\.io/team}' "$TEAM"

# -----------------------------------------------------------------------------
# STEP 4 - Verify initial small quotas and secure default NetworkPolicy.
# small must grant a total request budget of 2 CPU / 4Gi memory; with no
# networkProfile specified, only same-namespace and DNS egress are permitted.
# -----------------------------------------------------------------------------
log "STEP 4: Checking initial ResourceQuota and isolated NetworkPolicy..."
wait_for "Initial CPU request quota is 2" field_is resourcequota environment-quota \
  '{.spec.hard.requests\.cpu}' '2'
wait_for "Initial memory request quota is 4Gi" field_is resourcequota environment-quota \
  '{.spec.hard.requests\.memory}' '4Gi'
wait_for "NetworkPolicy has two egress rules (same namespace + DNS)" \
  field_is networkpolicy environment-network-policy \
  '{range .spec.egress[*]}x{end}' 'xx'
wait_for "NetworkPolicy permits DNS on UDP/53" \
  field_is networkpolicy environment-network-policy '{.spec.egress[1].ports[0].port}' '53'
wait_for "DNS selector targets CoreDNS" \
  field_is networkpolicy environment-network-policy \
  '{.spec.egress[1].to[0].podSelector.matchLabels.k8s-app}' 'kube-dns'

# -----------------------------------------------------------------------------
# STEP 5 - Test Kubernetes LimitRange and ResourceQuota admission.
# A Pod without requests/limits should receive small-profile defaults.
# A Pod requesting a CPU limit above the per-container maximum must be denied.
# A Pod with total requests above the 2-CPU namespace quota must be denied.
# All tests use server-side dry runs, so they create no Pods.
# -----------------------------------------------------------------------------
log "STEP 5: Testing LimitRange and ResourceQuota admission (server-side dry run)..."
pod_defaults="$(kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
  create --dry-run=server -f - \
  -o 'jsonpath={.spec.containers[0].resources.requests.cpu} {.spec.containers[0].resources.requests.memory} {.spec.containers[0].resources.limits.cpu} {.spec.containers[0].resources.limits.memory}' <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: e2e-defaults-check
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 60"]
YAML
)" || fail "Server-side dry run failed for Pod defaults."
[[ "$pod_defaults" == '100m 128Mi 500m 512Mi' ]] || \
  fail "Unexpected small LimitRange Pod defaults: ${pod_defaults}"
pass "LimitRange injects expected small-profile requests and limits."

if rejection="$(kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
  create --dry-run=server -f - -o name 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: e2e-too-much-cpu
spec:
  containers:
    - name: app
      image: busybox:1.36
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: '3'
          memory: 128Mi
YAML
)"; then
  fail "LimitRange unexpectedly accepted a container with a 3-CPU limit."
else
  [[ "$rejection" == *maximum* || "$rejection" == *Maximum* || \
     "$rejection" == *LimitRange* || "$rejection" == *'must be less'* ]] || \
    fail "Pod was rejected for an unexpected reason: ${rejection}"
  pass "LimitRange rejects CPU limits exceeding the allowed maximum."
fi

# Verify namespace ResourceQuota enforcement independently from LimitRange:
# three 1-CPU containers respect each container's limit but together request
# 3 CPUs, exceeding the initial small environment's total 2-CPU budget.
if quota_rejection="$(kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
  create --dry-run=server -f - -o name 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: e2e-over-quota
spec:
  containers:
    - name: app-1
      image: busybox:1.36
      resources:
        requests: {cpu: '1', memory: 128Mi}
        limits: {cpu: '1', memory: 128Mi}
    - name: app-2
      image: busybox:1.36
      resources:
        requests: {cpu: '1', memory: 128Mi}
        limits: {cpu: '1', memory: 128Mi}
    - name: app-3
      image: busybox:1.36
      resources:
        requests: {cpu: '1', memory: 128Mi}
        limits: {cpu: '1', memory: 128Mi}
YAML
)"; then
  fail "ResourceQuota unexpectedly accepted a Pod requesting 3 CPU (quota is 2)."
else
  [[ "$quota_rejection" == *'exceeded quota'* ]] || \
    fail "Over-quota Pod was rejected for an unexpected reason: ${quota_rejection}"
  pass "ResourceQuota rejects total Pod CPU requests exceeding the namespace budget."
fi

# -----------------------------------------------------------------------------
# STEP 6 - Test the provisioned RBAC using ServiceAccount impersonation.
# The deployer should create application Deployments but must not manage
# ResourceQuotas, RoleBindings, or Secrets. Verify its RoleBinding is correct.
# -----------------------------------------------------------------------------
log "STEP 6: Verifying deployer ServiceAccount RBAC permissions..."
wait_for "RoleBinding refers to environment-deployer Role" \
  field_is rolebinding environment-deployer '{.roleRef.name}' environment-deployer
wait_for "RoleBinding refers to environment-deployer ServiceAccount" \
  field_is rolebinding environment-deployer '{.subjects[0].name}' environment-deployer
permission_is yes create deployments.apps || fail "Deployer cannot create Deployments."
pass "Deployer can create Deployments."
permission_is no delete resourcequotas || fail "Deployer can delete ResourceQuotas."
pass "Deployer cannot delete ResourceQuotas."
permission_is no create rolebindings || fail "Deployer can create RoleBindings."
pass "Deployer cannot create RoleBindings."
permission_is no get secrets || fail "Deployer can read Secrets."
pass "Deployer cannot read Secrets."
permission_is no update networkpolicies.networking.k8s.io || \
  fail "Deployer can modify platform-managed NetworkPolicies."
pass "Deployer cannot update NetworkPolicies."

# -----------------------------------------------------------------------------
# STEP 7 - Update the SAME DevEnvironment XR (small -> medium and
# isolated -> standard). Verify Crossplane reconciles the existing ResourceQuota,
# LimitRange and NetworkPolicy instead of provisioning a new Namespace.
# -----------------------------------------------------------------------------
log "STEP 7: Updating environment size and network profile..."
kubectl --context "$KUBE_CONTEXT" patch devenvironment "$XR_NAME" --type merge \
  -p '{"spec":{"size":"medium","networkProfile":"standard"}}' >/dev/null
wait_for "Medium CPU request quota is 4" field_is resourcequota environment-quota \
  '{.spec.hard.requests\.cpu}' '4'
wait_for "Medium memory request quota is 8Gi" field_is resourcequota environment-quota \
  '{.spec.hard.requests\.memory}' '8Gi'
wait_for "Medium maximum CPU per container is 2" field_is limitrange environment-limits \
  '{.spec.limits[0].max.cpu}' '2'
wait_for "Standard NetworkPolicy has an additional HTTPS egress rule" \
  field_is networkpolicy environment-network-policy \
  '{range .spec.egress[*]}x{end}' 'xxx'
wait_for "Standard HTTPS egress uses TCP port 443" \
  field_is networkpolicy environment-network-policy \
  '{.spec.egress[2].ports[0].port}' '443'
wait_for "Standard HTTPS egress targets public IPv4 ranges" \
  field_is networkpolicy environment-network-policy \
  '{.spec.egress[2].to[0].ipBlock.cidr}' '0.0.0.0/0'
pass "Existing environment updated in place (size + networkProfile)."

# -----------------------------------------------------------------------------
# STEP 8 - Simulate manual drift and verify Crossplane restores desired state.
# Temporarily change the quota from 4 CPU to 1 CPU through Kubernetes. The XR
# still requests medium (4 CPU), so Crossplane should eventually correct it.
# -----------------------------------------------------------------------------
log "STEP 8: Testing reconciliation of a manually modified ResourceQuota..."
kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
  patch resourcequota environment-quota --type merge \
  -p '{"spec":{"hard":{"requests.cpu":"1"}}}' >/dev/null
wait_for "Crossplane restores CPU request quota to 4" \
  field_is resourcequota environment-quota '{.spec.hard.requests\.cpu}' '4'

# -----------------------------------------------------------------------------
# STEP 9 - Verify restrictive policy reconciliation (standard -> isolated).
# Switching back to isolated must REMOVE the previously allowed public HTTPS
# egress rule, not merely preserve old policy allowances.
# -----------------------------------------------------------------------------
log "STEP 9: Restoring isolated network profile and checking HTTPS rule removal..."
kubectl --context "$KUBE_CONTEXT" patch devenvironment "$XR_NAME" --type merge \
  -p '{"spec":{"networkProfile":"isolated"}}' >/dev/null
wait_for "Isolated policy removes public HTTPS egress rule" \
  field_is networkpolicy environment-network-policy \
  '{range .spec.egress[*]}x{end}' 'xx'

# -----------------------------------------------------------------------------
# STEP 10 - Delete the temporary XR and check full garbage collection.
# Crossplane should remove the Namespace and all seven namespaced resources.
# No preexisting environments are modified; cleanup also runs on early failures.
# -----------------------------------------------------------------------------
log "STEP 10: Deleting temporary XR and verifying Namespace cleanup..."
kubectl --context "$KUBE_CONTEXT" delete devenvironment "$XR_NAME" --wait=false
wait_for "DevEnvironment XR deleted" xr_absent
wait_for "Namespace and all namespaced resources deleted" namespace_absent
pass "Completed create -> verify -> update -> drift correction -> delete lifecycle."
