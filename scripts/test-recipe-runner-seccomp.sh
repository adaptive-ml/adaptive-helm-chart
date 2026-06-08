#!/usr/bin/env bash
# Verify the recipe-runner seccomp profile seam end-to-end on a real node.
#
# The operator (adaptive #5147) renders recipe-runner pods that reference a
# Localhost seccomp profile (localhostProfile: adaptive/recipe-runner.json).
# This chart ships that profile to every node's kubelet seccomp root via the
# recipe-runner-seccomp DaemonSet. Neither repo's CI exercises the join: if the
# DaemonSet does not place the file, the kubelet cannot resolve the Localhost
# reference and the pod fails to start (CreateContainerError).
#
# This test closes that gap. It installs the DaemonSet, then applies a pod that
# mimics the exact securityContext the operator renders (drop-ALL caps,
# runAsNonRoot 1000, automount off, Localhost profile) and asserts:
#   1. the DaemonSet installs the profile on the node,
#   2. the mimic pod reaches Running (kubelet resolved the profile),
#   3. the filter is actually loaded (Seccomp: 2 in /proc/self/status),
#   4. a pod referencing a missing profile does NOT start (so #2 is meaningful).
#
# Assumes a running single-node cluster (kind) with kubectl + helm on PATH.
# A NetworkPolicy-enforcing CNI is NOT required.

set -euo pipefail

CHART_DIR="${CHART_DIR:-./charts/adaptive}"
RELEASE="${RELEASE:-adaptive-test}"
NS="${NS:-seccomp-test}"
VALUES_BASE="${VALUES_BASE:-.github/test-values-base.yaml}"
# Mimic image: needs /proc/self/status + grep. Matches the netpol harness.
PROBE_IMAGE="${PROBE_IMAGE:-busybox:1.36}"
# Must match recipeRunner.seccompProfile.name in values.yaml.
PROFILE="${PROFILE:-adaptive/recipe-runner.json}"
START_TIMEOUT="${START_TIMEOUT:-120s}"
# How long to wait before concluding the negative-control pod will not start.
NEG_WAIT="${NEG_WAIT:-40}"

SECCOMP_YAML="$(mktemp)"
trap 'rm -f "$SECCOMP_YAML"' EXIT

group()    { printf '\n::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }
fail()     { printf '\n✗ FAIL: %s\n' "$*" >&2; exit 1; }
ok()       { printf '  ✓ %s\n' "$*"; }

group "Render recipe-runner seccomp DaemonSet from chart"
helm template "$RELEASE" "$CHART_DIR" \
  -f "$VALUES_BASE" \
  --namespace "$NS" \
  --set recipeRunner.seccompProfile.enabled=true \
  --show-only=templates/recipe-runner-seccomp-daemonset.yaml > "$SECCOMP_YAML"
cat "$SECCOMP_YAML"
endgroup

group "Install DaemonSet + profile ConfigMap"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$NS" -f "$SECCOMP_YAML"
DS="$(kubectl get ds -n "$NS" -l app.kubernetes.io/component=recipe-runner-seccomp \
  -o jsonpath='{.items[0].metadata.name}')"
[ -n "$DS" ] || fail "seccomp DaemonSet not created"
kubectl rollout status -n "$NS" "ds/$DS" --timeout="$START_TIMEOUT" \
  || fail "seccomp DaemonSet did not roll out"
# The installer logs a confirmation line once the profile is copied to the node.
# Logs can lag a moment behind the rollout, so poll rather than read once.
installed=false
for _ in $(seq 1 30); do
  if kubectl logs -n "$NS" -l app.kubernetes.io/component=recipe-runner-seccomp --tail=5 \
       2>/dev/null | grep -q "installed recipe-runner seccomp profile"; then
    installed=true; break
  fi
  sleep 2
done
[ "$installed" = true ] || fail "installer did not report writing the profile"
ok "DaemonSet installed the profile on the node"
endgroup

# Pod factory: the unprivileged recipe-runner securityContext, verbatim from the
# operator's pod-isolation snapshot (adaptive #5147). Arg $2 is the profile to
# reference, so the negative control can point at a missing one.
mimic_pod() {
  local name="$1" profile="$2"
  cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS
  labels:
    app.kubernetes.io/component: recipe-runner-gang
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  hostNetwork: false
  hostPID: false
  hostIPC: false
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    runAsNonRoot: true
    seccompProfile:
      type: Localhost
      localhostProfile: $profile
  containers:
    - name: main
      image: $PROBE_IMAGE
      command: ["sh", "-c", "grep Seccomp /proc/self/status; sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: false
        capabilities:
          drop: [ALL]
        seccompProfile:
          type: Localhost
          localhostProfile: $profile
EOF
}

group "Recipe-runner mimic pod starts with the Localhost profile"
mimic_pod recipe-runner-mimic "$PROFILE" | kubectl apply -f -
kubectl wait --for=condition=Ready pod/recipe-runner-mimic -n "$NS" \
  --timeout="$START_TIMEOUT" \
  || { kubectl describe pod/recipe-runner-mimic -n "$NS" || true
       fail "mimic pod did not start (kubelet could not resolve the Localhost profile?)"; }
ok "pod reached Running with seccompProfile=Localhost:$PROFILE"

# Seccomp: 2 == SECCOMP_MODE_FILTER -> a BPF filter is loaded for the process.
SECCOMP_MODE="$(kubectl logs -n "$NS" recipe-runner-mimic | awk '/Seccomp:/{print $2}')"
[ "$SECCOMP_MODE" = "2" ] \
  || fail "expected Seccomp mode 2 (filter), got '${SECCOMP_MODE:-<none>}'"
ok "filter is loaded in the container (Seccomp: 2)"
endgroup

group "Negative control: missing profile must NOT start"
mimic_pod recipe-runner-missing "adaptive/does-not-exist.json" | kubectl apply -f -
# The kubelet rejects container creation and keeps retrying; the pod never goes
# Ready. Give it a window, then assert it is still not Running.
if kubectl wait --for=condition=Ready pod/recipe-runner-missing -n "$NS" \
     --timeout="${NEG_WAIT}s" 2>/dev/null; then
  fail "pod with a missing Localhost profile unexpectedly started"
fi
PHASE="$(kubectl get pod/recipe-runner-missing -n "$NS" -o jsonpath='{.status.phase}')"
[ "$PHASE" != "Running" ] \
  || fail "pod with a missing Localhost profile is Running"
ok "pod with a missing profile correctly failed to start (phase=$PHASE)"
kubectl describe pod/recipe-runner-missing -n "$NS" 2>/dev/null \
  | grep -iE 'seccomp|cannot find|CreateContainerError' | head -3 || true
endgroup

printf '\n✓ PASS: recipe-runner seccomp profile seam verified end-to-end\n'
