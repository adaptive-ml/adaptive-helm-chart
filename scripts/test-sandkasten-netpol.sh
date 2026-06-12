#!/usr/bin/env bash
# Verify the chart's NetworkPolicies enforce the right egress rules. We render
# each component's policy with `helm template --show-only`, apply them to a
# fresh namespace, then spawn probe pods labeled as each component and assert
# allow/deny per egress rule with `nc -zv`.
#
# Probes:    sandkasten, control-plane, harmony, otel-collector.
# Assumes a running cluster with a NetworkPolicy-enforcing CNI (Cilium,
# Calico, ...) and `kubectl` + `helm` available on PATH.

set -euo pipefail

CHART_DIR="${CHART_DIR:-./charts/adaptive}"
RELEASE="${RELEASE:-adaptive-test}"
NS="${NS:-netpol-test}"
VALUES_BASE="${VALUES_BASE:-.github/test-values-base.yaml}"
VALUES_NETPOL="${VALUES_NETPOL:-.github/test-values-netpol.yaml}"
PROBE_IMAGE="${PROBE_IMAGE:-nicolaka/netshoot:v0.13}"
# busybox httpd binds to any port we ask for; useful when targets need to
# listen on the otel scrape ports (9009, 50053) in addition to the default.
TARGET_IMAGE="${TARGET_IMAGE:-busybox:1.36}"
NC_TIMEOUT="${NC_TIMEOUT:-5}"

NETPOL_YAML="$(mktemp)"
trap 'rm -f "$NETPOL_YAML"' EXIT

group()    { printf '\n::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }
fail()     { printf '\n✗ FAIL: %s\n' "$*" >&2; exit 1; }

POLICIES=(
  sandkasten-networkpolicy.yaml
  control-plane-networkpolicy.yaml
  harmony-networkpolicy.yaml
  otel-collector-networkpolicy.yaml
  recipe-runner-networkpolicy.yaml
)

# Detect Cilium: include the chart's CiliumNetworkPolicy for cp -> apiserver
# and pass `--api-versions cilium.io/v2` so the template's
# `.Capabilities.APIVersions.Has` gate evaluates true.
HELM_API_ARGS=()
IS_CILIUM=false
if kubectl api-resources --api-group=cilium.io 2>/dev/null \
    | grep -q CiliumNetworkPolicy; then
  IS_CILIUM=true
  HELM_API_ARGS+=(--api-versions cilium.io/v2)
  POLICIES+=(control-plane-cilium-networkpolicy.yaml)
  echo "  Cilium CRDs detected -> also rendering control-plane-cilium-networkpolicy.yaml"
fi

group "Render NetworkPolicies from chart"
: > "$NETPOL_YAML"
for tpl in "${POLICIES[@]}"; do
  helm template "$RELEASE" "$CHART_DIR" \
    -f "$VALUES_BASE" -f "$VALUES_NETPOL" \
    --namespace "$NS" \
    "${HELM_API_ARGS[@]}" \
    --show-only="templates/$tpl" >> "$NETPOL_YAML"
done
cat "$NETPOL_YAML"
endgroup

group "Apply NetworkPolicies and probe topology"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$NS" -f "$NETPOL_YAML"

# Pod factory. Probe pods (no port) run netshoot — has nc + dig + curl. Target
# pods (with a port) run `busybox httpd -p PORT` so Ready actually means
# "the TCP port is open" (via the tcpSocket readinessProbe).
make_pod() {
  local name="$1" component="$2" listen_port="${3:-}"
  if [[ -n "$listen_port" ]]; then
    cat <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS
  labels:
    app.kubernetes.io/name: adaptive
    app.kubernetes.io/instance: $RELEASE
    app.kubernetes.io/component: $component
spec:
  restartPolicy: Never
  containers:
    - name: main
      image: $TARGET_IMAGE
      command: ["httpd", "-f", "-p", "$listen_port"]
      ports:
        - containerPort: $listen_port
      readinessProbe:
        tcpSocket: { port: $listen_port }
        periodSeconds: 2
EOF
  else
    cat <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS
  labels:
    app.kubernetes.io/name: adaptive
    app.kubernetes.io/instance: $RELEASE
    app.kubernetes.io/component: $component
spec:
  restartPolicy: Never
  containers:
    - name: main
      image: $PROBE_IMAGE
      command: ["sleep", "3600"]
EOF
  fi
}

{
  # Probes (one per component whose policy we're testing).
  make_pod sandkasten-probe sandkasten
  make_pod cp-probe         control-plane
  make_pod harmony-probe    harmony
  make_pod otel-probe       otel-collector
  # Targets — one per component, listening on a "generic" port (8080) for the
  # bulk of assertions. cp/harmony get a second target on the otel scrape
  # ports because the otel policy is port-specific.
  make_pod cp-target            control-plane  8080
  make_pod cp-metrics-target    control-plane  9009
  make_pod harmony-target       harmony        8080
  make_pod harmony-metrics-tgt  harmony        50053
  make_pod otel-target          otel-collector 8080
  make_pod sandkasten-target    sandkasten     8080
  make_pod postgres-target      postgresql     8080
  make_pod redis-target         redis          8080
  make_pod mlflow-target        mlflow         8080
  make_pod other-target         unrelated      8080
  # OTLP backend on :4317 to prove the otel-collector's OTLP export egress
  # (always-on 4317/4318 to any destination) renders and is allowed.
  make_pod otlp-target          otlp-backend   4317
  # Recipe-runner pod-only isolation (HAR-162). One harmony-gang target listens
  # on the allowed WS port (50053) and another on a non-allowed port (8080) so
  # the deny assertion proves a policy drop, not a connection-refused. The probe
  # carries BOTH operator labels the policy podSelector matches.
  make_pod harmony-gang-target  harmony-gang   50053
  make_pod harmony-gang-8080    harmony-gang   8080
  # Operator-spawned inference partition: carries ONLY the adaptive.ml/*
  # operator labels (no chart name/instance labels), like the real pods the
  # control-plane creates at runtime. Listens on the mangrove port (50053)
  # the control-plane must reach for registration (PS-4870).
  cat <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: partition-target
  namespace: $NS
  labels:
    app.kubernetes.io/component: inference-partition
    adaptive.ml/managed-by: control-plane
spec:
  restartPolicy: Never
  containers:
    - name: main
      image: $TARGET_IMAGE
      command: ["httpd", "-f", "-p", "50053"]
      ports:
        - containerPort: 50053
      readinessProbe:
        tcpSocket: { port: 50053 }
        periodSeconds: 2
EOF
  cat <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: recipe-runner-probe
  namespace: $NS
  labels:
    app.kubernetes.io/name: adaptive
    app.kubernetes.io/instance: $RELEASE
    app.kubernetes.io/component: recipe-runner-gang
    adaptive.ml/managed-by: control-plane
spec:
  restartPolicy: Never
  containers:
    - name: main
      image: $PROBE_IMAGE
      command: ["sleep", "3600"]
EOF
} | kubectl apply -f -

kubectl wait --for=condition=Ready pod --all -n "$NS" --timeout=180s
endgroup

get_ip() { kubectl get pod -n "$NS" "$1" -o jsonpath='{.status.podIP}'; }

CP_IP=$(get_ip cp-target)
CP_METRICS_IP=$(get_ip cp-metrics-target)
HARMONY_IP=$(get_ip harmony-target)
HARMONY_METRICS_IP=$(get_ip harmony-metrics-tgt)
OTEL_IP=$(get_ip otel-target)
SAND_IP=$(get_ip sandkasten-target)
PG_IP=$(get_ip postgres-target)
REDIS_IP=$(get_ip redis-target)
MLFLOW_IP=$(get_ip mlflow-target)
OTHER_IP=$(get_ip other-target)
OTLP_IP=$(get_ip otlp-target)
HGANG_IP=$(get_ip harmony-gang-target)
HGANG8080_IP=$(get_ip harmony-gang-8080)
PARTITION_IP=$(get_ip partition-target)
KUBE_API_IP=$(kubectl get svc -n default kubernetes -o jsonpath='{.spec.clusterIP}')

# `nc -zv` returns 0 on connect, non-zero on refused/timeout. We wrap in
# `timeout` so a silent NetworkPolicy drop (no RST) doesn't hang forever.
probe_tcp_from() {
  local probe="$1" ip="$2" port="$3"
  kubectl exec -n "$NS" "$probe" -- \
    timeout "$NC_TIMEOUT" nc -zv "$ip" "$port" >/dev/null 2>&1
}

assert_from() {
  local expect="$1" probe="$2" label="$3" ip="$4" port="$5"
  printf '  [%-5s] %-28s %s:%s ... ' "$expect" "$label" "$ip" "$port"
  if probe_tcp_from "$probe" "$ip" "$port"; then
    if [[ "$expect" == "allow" ]]; then printf 'ok\n'
    else                                  printf 'FAIL (expected deny)\n'; return 1
    fi
  else
    if [[ "$expect" == "deny" ]]; then    printf 'ok\n'
    else                                  printf 'FAIL (expected allow)\n'; return 1
    fi
  fi
}

failed=0

group "sandkasten egress (cp/harmony/otel/redis/mlflow/DNS/internet)"
assert_from allow sandkasten-probe "control-plane"  "$CP_IP"        8080 || failed=1
assert_from allow sandkasten-probe "harmony"        "$HARMONY_IP"   8080 || failed=1
assert_from allow sandkasten-probe "otel-collector" "$OTEL_IP"      8080 || failed=1
assert_from allow sandkasten-probe "redis"          "$REDIS_IP"     8080 || failed=1
assert_from allow sandkasten-probe "mlflow"         "$MLFLOW_IP"    8080 || failed=1
# DNS: verify the probe can resolve in-cluster names via CoreDNS.
printf '  [%-5s] %-28s %s ... ' "allow" "DNS lookup" "kubernetes.default"
if kubectl exec -n "$NS" sandkasten-probe -- timeout "$NC_TIMEOUT" \
    nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
  printf 'ok\n'
else
  printf 'FAIL\n'; failed=1
fi
# Internet: 1.1.1.1 (Cloudflare DNS) is outside the carved-out RFC1918 /
# link-local / CGNAT ranges, so the ipBlock rule should allow TCP/443.
assert_from allow sandkasten-probe "internet (1.1.1.1)" "1.1.1.1"    443  || failed=1
assert_from deny  sandkasten-probe "postgres"           "$PG_IP"     8080 || failed=1
assert_from deny  sandkasten-probe "kubernetes API"     "$KUBE_API_IP" 443 || failed=1
assert_from deny  sandkasten-probe "unrelated"          "$OTHER_IP"  8080 || failed=1
endgroup

group "control-plane egress (in-cluster, internet)"
assert_from allow cp-probe "control-plane (self)" "$CP_IP"       8080 || failed=1
assert_from allow cp-probe "sandkasten"           "$SAND_IP"     8080 || failed=1
assert_from allow cp-probe "redis"                "$REDIS_IP"    8080 || failed=1
assert_from allow cp-probe "postgres"             "$PG_IP"       8080 || failed=1
assert_from allow cp-probe "otel-collector"       "$OTEL_IP"     8080 || failed=1
assert_from allow cp-probe "mlflow"               "$MLFLOW_IP"   8080 || failed=1
assert_from allow cp-probe "internet (1.1.1.1)"   "1.1.1.1"      443  || failed=1
# Harmony: control-plane must reach the harmony workers to accept their
# compute-pool registration (it health-checks the worker's service port).
# Without this the pool registration is rejected with a 500 and the pool
# never comes up.
assert_from allow cp-probe "harmony"              "$HARMONY_IP"  8080 || failed=1
# Operator-spawned partition (adaptive.ml/managed-by label, no chart labels).
assert_from allow cp-probe "inference partition"  "$PARTITION_IP" 50053 || failed=1
assert_from deny  cp-probe "unrelated"            "$OTHER_IP"    8080 || failed=1
# cp → kube-apiserver reachability.
#
# On Cilium, the chart ships a CiliumNetworkPolicy (toEntities:
# [kube-apiserver]) that allows this identity-based, independent of port —
# so we assert it succeeds. This is the case the standard NetworkPolicy
# cannot express (Cilium does not cover the apiserver identity with any
# ipBlock 0.0.0.0/0 rule).
#
# On Calico / Antrea (and in this kind-based CI generally) we do NOT
# assert it: kube-proxy DNATs the apiserver Service (10.96.0.1:443) to the
# kind control-plane node on :6443, and these CNIs enforce egress on a
# tuple that the chart's `0.0.0.0/0:443` rule doesn't match (port 6443 !=
# 443). Real clusters where the apiserver actually listens on :443 are
# covered by that rule; the kind :6443 remap is a test-env artifact, not a
# chart gap, so asserting here would be testing kind, not the chart.
if [[ "$IS_CILIUM" == "true" ]]; then
  assert_from allow cp-probe "kubernetes API"     "$KUBE_API_IP" 443  || failed=1
fi
endgroup

group "harmony egress (self, control-plane, redis, otel, DNS, internet)"
assert_from allow harmony-probe "harmony (self)"     "$HARMONY_IP"  8080 || failed=1
assert_from allow harmony-probe "control-plane"      "$CP_IP"       8080 || failed=1
assert_from allow harmony-probe "redis"              "$REDIS_IP"    8080 || failed=1
assert_from allow harmony-probe "otel-collector"     "$OTEL_IP"     8080 || failed=1
assert_from allow harmony-probe "internet (1.1.1.1)" "1.1.1.1"      443  || failed=1
assert_from deny  harmony-probe "mlflow"             "$MLFLOW_IP"   8080 || failed=1
assert_from deny  harmony-probe "sandkasten"         "$SAND_IP"     8080 || failed=1
assert_from deny  harmony-probe "postgres"           "$PG_IP"       8080 || failed=1
assert_from deny  harmony-probe "kubernetes API"     "$KUBE_API_IP" 443  || failed=1
assert_from deny  harmony-probe "unrelated"          "$OTHER_IP"    8080 || failed=1
endgroup

group "otel-collector egress (scrape ports, DNS, internet)"
assert_from allow otel-probe "control-plane :9009"  "$CP_METRICS_IP"      9009  || failed=1
assert_from allow otel-probe "harmony :50053"       "$HARMONY_METRICS_IP" 50053 || failed=1
assert_from allow otel-probe "internet (1.1.1.1)"   "1.1.1.1"             443   || failed=1
# OTLP export (gRPC :4317) to an arbitrary peer: the collector ships telemetry
# to a cross-namespace or remote backend, always allowed on 4317/4318.
assert_from allow otel-probe "otlp export :4317"    "$OTLP_IP"            4317  || failed=1
# Same pods, wrong ports — netpol is port-specific for the otel scrape rules.
assert_from deny  otel-probe "control-plane :8080"  "$CP_IP"              8080  || failed=1
assert_from deny  otel-probe "harmony :8080"        "$HARMONY_IP"         8080  || failed=1
assert_from deny  otel-probe "sandkasten"           "$SAND_IP"            8080  || failed=1
assert_from deny  otel-probe "postgres"             "$PG_IP"              8080  || failed=1
assert_from deny  otel-probe "redis"                "$REDIS_IP"           8080  || failed=1
assert_from deny  otel-probe "mlflow"               "$MLFLOW_IP"          8080  || failed=1
assert_from deny  otel-probe "kubernetes API"       "$KUBE_API_IP"        443   || failed=1
assert_from deny  otel-probe "unrelated"            "$OTHER_IP"           8080  || failed=1
endgroup

group "recipe-runner egress (harmony-gang WS, cp/otel/mlflow, DNS, internet)"
# The runner's WS endpoint is the gang master on :50053.
assert_from allow recipe-runner-probe "harmony-gang :50053" "$HGANG_IP"  50053 || failed=1
assert_from allow recipe-runner-probe "control-plane"       "$CP_IP"     8080  || failed=1
assert_from allow recipe-runner-probe "otel-collector"      "$OTEL_IP"   8080  || failed=1
assert_from allow recipe-runner-probe "mlflow"              "$MLFLOW_IP" 8080  || failed=1
assert_from allow recipe-runner-probe "internet (1.1.1.1)"  "1.1.1.1"    443   || failed=1
printf '  [%-5s] %-28s %s ... ' "allow" "DNS lookup" "kubernetes.default"
if kubectl exec -n "$NS" recipe-runner-probe -- timeout "$NC_TIMEOUT" \
    nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
  printf 'ok\n'
else
  printf 'FAIL\n'; failed=1
fi
# Recipe runner has no redis egress (unlike sandkasten) and must not reach
# the gang master on non-WS ports, postgres, the apiserver, or unrelated pods.
assert_from deny  recipe-runner-probe "harmony-gang :8080" "$HGANG8080_IP" 8080 || failed=1
assert_from deny  recipe-runner-probe "redis"              "$REDIS_IP"    8080 || failed=1
assert_from deny  recipe-runner-probe "sandkasten"         "$SAND_IP"     8080 || failed=1
assert_from deny  recipe-runner-probe "postgres"           "$PG_IP"       8080 || failed=1
assert_from deny  recipe-runner-probe "kubernetes API"     "$KUBE_API_IP" 443  || failed=1
assert_from deny  recipe-runner-probe "unrelated"          "$OTHER_IP"    8080 || failed=1
endgroup

if [[ $failed -ne 0 ]]; then
  fail "one or more NetworkPolicy assertions failed"
fi
echo
echo "All NetworkPolicy assertions passed."
