#!/usr/bin/env bash
# Static reachability check for the chart's NetworkPolicies. Renders the
# chart, then runs np-guard/netpol-analyzer's `netpolicy list` over the
# rendered manifests to compute who-can-reach-whom and asserts a subset
# of the expected allow/deny matrix.
#
# Runs without a cluster — pure static analysis. Catches policy bugs
# (selectors that match nothing, unreachable pods, etc.) before the
# dynamic CNI matrix runs. Vanilla NP semantics, so any deviation from
# this matrix on a real CNI indicates a CNI-specific quirk worth
# documenting.

set -euo pipefail

CHART_DIR="${CHART_DIR:-./charts/adaptive}"
RELEASE="${RELEASE:-adaptive-test}"
NS="${NS:-netpol-test}"
VALUES_BASE="${VALUES_BASE:-.github/test-values-base.yaml}"
VALUES_NETPOL="${VALUES_NETPOL:-.github/test-values-netpol.yaml}"
NETPOLICY_BIN="${NETPOLICY_BIN:-netpolicy}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

group()    { printf '\n::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }

group "Render chart"
helm template "$RELEASE" "$CHART_DIR" \
  -f "$VALUES_BASE" -f "$VALUES_NETPOL" \
  --namespace "$NS" \
  > "$WORKDIR/manifests.yaml"
echo "rendered $(wc -l < "$WORKDIR/manifests.yaml") lines"

# Synthetic operator-spawned workload. Inference partitions / gangs are
# created at runtime by the control-plane with adaptive.ml/* labels (not the
# chart's selector labels) and never appear in the rendered manifests, so
# inject one for the reachability analysis.
cat > "$WORKDIR/partition.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${RELEASE}-inference-partition
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: inference-partition
      adaptive.ml/managed-by: control-plane
  template:
    metadata:
      labels:
        app.kubernetes.io/component: inference-partition
        adaptive.ml/managed-by: control-plane
    spec:
      containers:
        - name: mangrove
          image: busybox
          ports:
            - containerPort: 50053
EOF
endgroup

group "Compute reachability (netpolicy list)"
"$NETPOLICY_BIN" list --dirpath "$WORKDIR" -o txt > "$WORKDIR/connlist.txt"
cat "$WORKDIR/connlist.txt"
endgroup

CONN="$WORKDIR/connlist.txt"
NS_PREFIX="$NS/$RELEASE"

has_edge() {
  local src="$1" dst="$2"
  grep -qE "${NS_PREFIX}-${src}\b.* => ${NS_PREFIX}-${dst}\b" "$CONN"
}

# "Internet" = any ipBlock destination starting at 0.0.0.0 (a range that
# includes public IPv4). netpolicy decomposes `0.0.0.0/0` allow rules
# into adjacent CIDR ranges, slicing at the boundaries of other ipBlock
# rules in the policy. Whatever the boundary, the lowest range always
# starts at `0.0.0.0-`, so we anchor on that.
has_internet() {
  local src="$1"
  grep -qE "${NS_PREFIX}-${src}\b.* => 0\.0\.0\.0[-/]" "$CONN"
}

assert_allow() {
  local src="$1" dst="$2"
  printf '  [allow] %-22s => %-22s ... ' "$src" "$dst"
  if has_edge "$src" "$dst"; then printf 'ok\n'
  else printf 'FAIL (no edge found)\n'; return 1
  fi
}

assert_deny() {
  local src="$1" dst="$2"
  printf '  [deny ] %-22s => %-22s ... ' "$src" "$dst"
  if has_edge "$src" "$dst"; then printf 'FAIL (unexpected edge)\n'; return 1
  else printf 'ok\n'
  fi
}

assert_internet_allow() {
  local src="$1"
  printf '  [allow] %-22s => %-22s ... ' "$src" "internet"
  if has_internet "$src"; then printf 'ok\n'
  else printf 'FAIL (no internet edge)\n'; return 1
  fi
}

failed=0

group "sandkasten egress"
assert_allow         sandkasten      controlplane    || failed=1
assert_allow         sandkasten      harmony-default || failed=1
assert_allow         sandkasten      otel-collector  || failed=1
assert_allow         sandkasten      redis           || failed=1
assert_allow         sandkasten      mlflow          || failed=1
assert_internet_allow sandkasten                     || failed=1
assert_deny          sandkasten      postgresql      || failed=1
endgroup

group "control-plane egress"
assert_allow         controlplane    sandkasten      || failed=1
assert_allow         controlplane    redis           || failed=1
assert_allow         controlplane    postgresql      || failed=1
assert_allow         controlplane    otel-collector  || failed=1
assert_allow         controlplane    mlflow          || failed=1
assert_internet_allow controlplane                   || failed=1
# control-plane must reach harmony to accept compute-pool registration
# (health-checks the worker service port). Without it registration is
# rejected with a 500 and the pool never comes up.
assert_allow         controlplane    harmony-default || failed=1
# Same registration flow for operator-spawned partitions/gangs, which carry
# adaptive.ml/managed-by=control-plane instead of the chart harmony labels.
# Missing this rule broke preprod inference partitions (PS-4870).
assert_allow         controlplane    inference-partition || failed=1
endgroup

group "harmony egress"
assert_allow         harmony-default controlplane    || failed=1
assert_allow         harmony-default redis           || failed=1
assert_allow         harmony-default otel-collector  || failed=1
assert_internet_allow harmony-default                || failed=1
assert_deny          harmony-default sandkasten      || failed=1
assert_deny          harmony-default mlflow          || failed=1
assert_deny          harmony-default postgresql      || failed=1
endgroup

group "otel-collector egress"
assert_allow         otel-collector  controlplane    || failed=1
assert_allow         otel-collector  harmony-default || failed=1
assert_internet_allow otel-collector                 || failed=1
assert_deny          otel-collector  sandkasten      || failed=1
assert_deny          otel-collector  redis           || failed=1
assert_deny          otel-collector  mlflow          || failed=1
assert_deny          otel-collector  postgresql      || failed=1
endgroup

if [[ $failed -ne 0 ]]; then
  printf '\n✗ static reachability check failed\n' >&2
  exit 1
fi
printf '\nAll static reachability assertions passed.\n'
