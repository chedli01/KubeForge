#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"

ensure_context

# Usage: bash scripts/test-networkpolicy.sh [isolated-namespace] [standard-namespace]
ISOLATED_NS="${1:-payments-dev}"
STANDARD_NS="${2:-network-test}"
PUBLIC_IP="${PUBLIC_IP:-1.1.1.1}"
PUBLIC_PORT="${PUBLIC_PORT:-443}"

[[ "$ISOLATED_NS" != "$STANDARD_NS" ]] || fail "Choose two different namespaces."

# Unique names avoid touching any existing application Pods.
RUN_ID="$(date +%s)-$$"
PREFIX="kubeforge-nettest-${RUN_ID}"
ISOLATED_SERVER="${PREFIX}-server"
ISOLATED_CLIENT="${PREFIX}-client"
STANDARD_SERVER="${PREFIX}-server"
STANDARD_CLIENT="${PREFIX}-client"
PODS_CREATED=false

cleanup() {
  if [[ "$PODS_CREATED" == true ]]; then
    log "Cleaning up temporary test Pods..."
    kubectl --context "$KUBE_CONTEXT" -n "$ISOLATED_NS" delete pod \
      "$ISOLATED_SERVER" "$ISOLATED_CLIENT" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl --context "$KUBE_CONTEXT" -n "$STANDARD_NS" delete pod \
      "$STANDARD_SERVER" "$STANDARD_CLIENT" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Check the profile selected by each DevEnvironment XR.
check_profile() {
  local ns="$1" expected="$2" actual
  kubectl --context "$KUBE_CONTEXT" get "devenvironment/$ns" >/dev/null || \
    fail "Missing DevEnvironment/$ns."
  actual="$(kubectl --context "$KUBE_CONTEXT" \
    get "devenvironment/$ns" -o jsonpath='{.spec.networkProfile}')"
  actual="${actual:-isolated}"
  [[ "$actual" == "$expected" ]] || \
    fail "DevEnvironment/$ns uses networkProfile='$actual', expected '$expected'."
  kubectl --context "$KUBE_CONTEXT" -n "$ns" \
    get networkpolicy environment-network-policy >/dev/null || \
    fail "Missing environment-network-policy in namespace '$ns'."
  log "PASS: $ns is configured with the $expected profile and its NetworkPolicy exists."
}

log "Checking KubeForge network profiles..."
check_profile "$ISOLATED_NS" isolated
check_profile "$STANDARD_NS" standard

# A local HTTP server and a client in EACH namespace let us test
# communication in both directions. No Services or app workloads are changed.
create_pods() {
  local ns="$1" server="$2" client="$3"
  kubectl --context "$KUBE_CONTEXT" -n "$ns" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ${server}
  labels:
    app.kubernetes.io/part-of: kubeforge-networkpolicy-test
spec:
  automountServiceAccountToken: false
  terminationGracePeriodSeconds: 1
  containers:
    - name: http
      image: python:3.12-alpine
      command: ["python3", "-u", "-m", "http.server", "8080", "--bind", "0.0.0.0"]
      ports:
        - containerPort: 8080
      readinessProbe:
        httpGet:
          path: /
          port: 8080
        periodSeconds: 2
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile:
          type: RuntimeDefault
---
apiVersion: v1
kind: Pod
metadata:
  name: ${client}
  labels:
    app.kubernetes.io/part-of: kubeforge-networkpolicy-test
spec:
  automountServiceAccountToken: false
  terminationGracePeriodSeconds: 1
  containers:
    - name: client
      image: python:3.12-alpine
      command: ["python3", "-u", "-c", "import time; time.sleep(3600)"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile:
          type: RuntimeDefault
YAML
}

log "Creating temporary test Pods (image: python:3.12-alpine)..."
# Mark before creation so partially created Pods are cleaned up on failure.
PODS_CREATED=true
create_pods "$ISOLATED_NS" "$ISOLATED_SERVER" "$ISOLATED_CLIENT"
create_pods "$STANDARD_NS" "$STANDARD_SERVER" "$STANDARD_CLIENT"

for ns in "$ISOLATED_NS" "$STANDARD_NS"; do
  log "Waiting for test Pods in $ns..."
  kubectl --context "$KUBE_CONTEXT" -n "$ns" \
    wait --for=condition=Ready "pod/${PREFIX}-server" --timeout=180s || \
    fail "Server Pod did not become Ready in $ns."
  kubectl --context "$KUBE_CONTEXT" -n "$ns" \
    wait --for=condition=Ready "pod/${PREFIX}-client" --timeout=180s || \
    fail "Client Pod did not become Ready in $ns."
done

log "Waiting 30 seconds for CNI NetworkPolicy enforcement..."
sleep 30

ISOLATED_IP="$(kubectl --context "$KUBE_CONTEXT" -n "$ISOLATED_NS" \
  get pod "$ISOLATED_SERVER" -o jsonpath='{.status.podIP}')"
STANDARD_IP="$(kubectl --context "$KUBE_CONTEXT" -n "$STANDARD_NS" \
  get pod "$STANDARD_SERVER" -o jsonpath='{.status.podIP}')"
[[ -n "$ISOLATED_IP" && -n "$STANDARD_IP" ]] || fail "Could not retrieve test Pod IPs."

# Use Python already available inside the temporary Pod. Exit status 42
# means a TCP connection failed. Other exit statuses indicate test problems.
probe_tcp() {
  local ns="$1" pod="$2" host="$3" port="$4"
  kubectl --context "$KUBE_CONTEXT" -n "$ns" exec -i "$pod" -- \
    python3 - "$host" "$port" <<'PY'
import socket
import sys
host, port = sys.argv[1], int(sys.argv[2])
try:
    with socket.create_connection((host, port), timeout=4):
        print("CONNECTED")
except OSError as exc:
    print(f"CONNECTION_FAILED: {type(exc).__name__}: {exc}")
    sys.exit(42)
PY
}

assert_allowed() {
  local title="$1" ns="$2" pod="$3" host="$4" port="$5" result
  if result="$(probe_tcp "$ns" "$pod" "$host" "$port" 2>&1)"; then
    log "PASS: $title (connected to $host:$port)."
  else
    fail "$title: expected connection to succeed. Details: $result"
  fi
}

assert_denied() {
  local title="$1" ns="$2" pod="$3" host="$4" port="$5" result rc=0
  result="$(probe_tcp "$ns" "$pod" "$host" "$port" 2>&1)" || rc=$?
  if [[ "$rc" -eq 42 ]]; then
    log "PASS: $title (connection blocked)."
  elif [[ "$rc" -eq 0 ]]; then
    fail "$title: unexpected connection succeeded ($host:$port). NetworkPolicy may not be enforced."
  else
    fail "$title: probe failed unexpectedly (exit=$rc). Details: $result"
  fi
}

probe_dns() {
  local ns="$1" pod="$2"
  kubectl --context "$KUBE_CONTEXT" -n "$ns" exec -i "$pod" -- \
    python3 - <<'PY'
import socket
socket.getaddrinfo("kubernetes.default.svc.cluster.local", 443)
print("DNS_RESOLVED")
PY
}

log "TEST 1: Allow connectivity within each Namespace..."
assert_allowed "isolated: same-namespace Pod connection" \
  "$ISOLATED_NS" "$ISOLATED_CLIENT" "$ISOLATED_IP" 8080
assert_allowed "standard: same-namespace Pod connection" \
  "$STANDARD_NS" "$STANDARD_CLIENT" "$STANDARD_IP" 8080

log "TEST 2: Block connections between development Namespaces..."
assert_denied "isolated -> standard" \
  "$ISOLATED_NS" "$ISOLATED_CLIENT" "$STANDARD_IP" 8080
assert_denied "standard -> isolated" \
  "$STANDARD_NS" "$STANDARD_CLIENT" "$ISOLATED_IP" 8080

log "TEST 3: Allow Kubernetes DNS from both profiles..."
for ns in "$ISOLATED_NS" "$STANDARD_NS"; do
  if output="$(probe_dns "$ns" "$PREFIX-client" 2>&1)"; then
    log "PASS: DNS resolution from $ns."
  else
    fail "DNS resolution failed from $ns. Details: $output"
  fi
done

log "TEST 4: Check public TCP/443 egress ($PUBLIC_IP:$PUBLIC_PORT)..."
# First check that the isolated profile denies it.
assert_denied "isolated: public TCP/443 denied" \
  "$ISOLATED_NS" "$ISOLATED_CLIENT" "$PUBLIC_IP" "$PUBLIC_PORT"

# If the standard profile cannot connect either, external connectivity may
# be unavailable from this kind cluster. That is INCONCLUSIVE, not PASS.
if output="$(probe_tcp "$STANDARD_NS" "$STANDARD_CLIENT" "$PUBLIC_IP" "$PUBLIC_PORT" 2>&1)"; then
  log "PASS: standard profile permits public TCP/443 connectivity."
else
  printf '\n[INCONCLUSIVE] Standard profile could not reach %s:%s.\n' \
    "$PUBLIC_IP" "$PUBLIC_PORT" >&2
  printf '[INCONCLUSIVE] External routing/firewall/proxy could be responsible: %s\n' \
    "$output" >&2
  printf '[INCONCLUSIVE] Internal Pod isolation and DNS tests passed; external egress is unverified.\n' >&2
  exit 2
fi

log "SUCCESS: NetworkPolicy provisioning and enforcement tests passed."
log "Temporary test Pods will be deleted automatically."
