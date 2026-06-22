#!/usr/bin/env bash
# Assert the chart emits an egress NetworkPolicy for every operator-spawned
# pod component.
#
# The control plane spawns pods that run the harmony workload but carry
# control-plane labels (adaptive.ml/managed-by=control-plane) instead of the
# chart's name/instance selector labels:
#   - app.kubernetes.io/component=harmony-gang        (gang training)
#   - app.kubernetes.io/component=inference-partition (inference serving)
#
# These have no workload object in the chart, so the dynamic CNI matrix and
# the np-guard reachability check (both workload-driven) never see them. They
# only acquire a NetworkPolicy if the chart selects them by label.
#
# Why this matters: as soon as ANY egress policy selects one of these pods it
# flips to default-deny egress (vanilla NetworkPolicy and Cilium both). In
# production the otel DDOT CiliumClusterwideNetworkPolicy selects them to allow
# Datadog agent egress, which silently turned their egress default-deny and
# broke the mangrove S3 preflight (gang pods exited 1 on an S3 connect
# timeout). The fix is the chart granting these components the same egress as
# harmony. This check fails the build if that coverage regresses or if a new
# operator-spawned component is added without it.
#
# Pure static analysis over `helm template` output; no cluster needed.

set -euo pipefail

CHART_DIR="${CHART_DIR:-./charts/adaptive}"
RELEASE="${RELEASE:-adaptive-test}"
NS="${NS:-netpol-test}"
VALUES_BASE="${VALUES_BASE:-.github/test-values-base.yaml}"
VALUES_NETPOL="${VALUES_NETPOL:-.github/test-values-netpol.yaml}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

printf '::group::Render chart\n'
helm template "$RELEASE" "$CHART_DIR" \
  -f "$VALUES_BASE" -f "$VALUES_NETPOL" \
  --namespace "$NS" \
  > "$WORKDIR/manifests.yaml"
echo "rendered $(wc -l < "$WORKDIR/manifests.yaml") lines"
printf '::endgroup::\n'

python3 "$(dirname "$0")/check-operator-pod-egress.py" "$WORKDIR/manifests.yaml"
