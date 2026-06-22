#!/usr/bin/env python3
"""Assert every operator-spawned pod component has chart egress coverage.

Reads a rendered `helm template` manifest (multi-doc YAML) and checks that
each control-plane-managed component listed in REQUIRED_COMPONENTS is selected
by an Egress NetworkPolicy that grants the destinations its mangrove preflight
needs (cluster DNS, the control plane, and an S3 path).

Source of truth for the component list is the otel DDOT
CiliumClusterwideNetworkPolicy (k8s-infrastructure) — the policy that selects
these pods in production and flips them to default-deny. Any component it
selects must appear here and get chart egress, or the build fails.
"""

import sys

import yaml

COMPONENT_LABEL = "app.kubernetes.io/component"
MANAGED_BY_LABEL = "adaptive.ml/managed-by"
MANAGED_BY_VALUE = "control-plane"

# Operator-spawned components that carry control-plane labels instead of the
# chart selector labels. Keep in sync with the DDOT clusterwide policy.
REQUIRED_COMPONENTS = ["harmony-gang", "inference-partition"]

# S3 / external object storage is reachable either via the internal
# s3proxy/minio services or directly over the internet (external S3 / HF).
S3_COMPONENTS = {"s3proxy", "minio"}
INTERNET_CIDR = "0.0.0.0/0"


def pod_selector_matches(selector: dict, component: str) -> bool:
    """True if a podSelector targets `component` AND is scoped to control-plane managed pods."""
    if not selector:
        return False
    labels = selector.get("matchLabels") or {}
    if labels.get(MANAGED_BY_LABEL) != MANAGED_BY_VALUE:
        return False
    if labels.get(COMPONENT_LABEL) == component:
        return True
    for expr in selector.get("matchExpressions") or []:
        if (
            expr.get("key") == COMPONENT_LABEL
            and expr.get("operator") == "In"
            and component in (expr.get("values") or [])
        ):
            return True
    return False


def egress_targets_component(egress: list, component: str) -> bool:
    for rule in egress or []:
        for to in rule.get("to") or []:
            sel = to.get("podSelector") or {}
            if (sel.get("matchLabels") or {}).get(COMPONENT_LABEL) == component:
                return True
    return False


def egress_has_dns(egress: list) -> bool:
    for rule in egress or []:
        for port in rule.get("ports") or []:
            if port.get("port") == 53:
                return True
    return False


def egress_has_s3(egress: list) -> bool:
    for rule in egress or []:
        for to in rule.get("to") or []:
            block = to.get("ipBlock") or {}
            if block.get("cidr") == INTERNET_CIDR and any(
                p.get("port") in (443, 80) for p in rule.get("ports") or []
            ):
                return True
            sel = to.get("podSelector") or {}
            if (sel.get("matchLabels") or {}).get(COMPONENT_LABEL) in S3_COMPONENTS:
                return True
    return False


def main(path: str) -> int:
    with open(path) as f:
        policies = [
            d
            for d in yaml.safe_load_all(f)
            if d and d.get("kind") == "NetworkPolicy"
        ]

    failed = False
    for component in REQUIRED_COMPONENTS:
        print(f"::group::Operator-pod egress coverage: {component}")
        matching = [
            p
            for p in policies
            if "Egress" in (p.get("spec", {}).get("policyTypes") or [])
            and pod_selector_matches(p.get("spec", {}).get("podSelector", {}), component)
        ]
        if not matching:
            print(
                f"  FAIL no Egress NetworkPolicy selects component={component} "
                f"with {MANAGED_BY_LABEL}={MANAGED_BY_VALUE}"
            )
            print("::endgroup::")
            failed = True
            continue

        # Coverage is the union of every policy that selects the component
        # (NetworkPolicy egress is additive).
        egress = [r for p in matching for r in (p["spec"].get("egress") or [])]
        names = ", ".join(p["metadata"]["name"] for p in matching)
        print(f"  selected by: {names}")

        checks = {
            "cluster DNS": egress_has_dns(egress),
            "control plane": egress_targets_component(egress, "control-plane"),
            "S3 (internet :443/:80 or s3proxy/minio)": egress_has_s3(egress),
        }
        for label, ok in checks.items():
            print(f"  [{'ok' if ok else 'FAIL'}] egress to {label}")
            failed = failed or not ok
        print("::endgroup::")

    if failed:
        print("\n✗ operator-pod egress coverage check failed", file=sys.stderr)
        return 1
    print("\nAll operator-pod egress coverage assertions passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: check-operator-pod-egress.py <rendered-manifests.yaml>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
