# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Helm chart repository for deploying Adaptive Engine, an ML platform. It contains two charts:
- **adaptive** - Main chart for deploying Adaptive Engine (control plane, harmony workers, sandkasten sandbox service, MLflow, Redis, optionally PostgreSQL)
- **monitoring** - Optional addon chart for Grafana/Loki/Promtail monitoring stack

## Common Commands

### Linting and Validation

```bash
# Lint charts with chart-testing (requires ct installed)
ct lint --target-branch main

# Lint charts with Artifact Hub linter
ah lint ./charts

# Validate with kubeconform
helm template adaptive ./charts/adaptive | kubeconform -strict -schema-location default -summary
```

### Local Testing

```bash
# Dry-run install to test template rendering
helm install --dry-run --debug adaptive-stack ./charts/adaptive

# With specific options enabled
helm install --dry-run --debug adaptive-stack ./charts/adaptive --set mlflow.enabled=true
helm install --dry-run --debug adaptive-stack ./charts/adaptive --set installPostgres.enabled=true

# With external values file
helm install --dry-run --debug adaptive-stack ./charts/adaptive -f values-override.yaml

# Template only (no install)
helm template adaptive-test ./charts/adaptive
```

### Update Dependencies

```bash
helm dependency update ./charts/adaptive
helm dependency update ./charts/monitoring
```

### TOC Generation

When modifying markdown files with headers, regenerate table of contents:
```bash
./scripts/generate-toc.sh
```

CI checks that TOCs are up-to-date on every PR.

## Architecture

### Adaptive Chart Structure

The main chart deploys these components:

1. **Control Plane** (`control-plane-dpl.yaml`, `control-plane-svc.yaml`)
   - Web UI and API server
   - Manages jobs, users, and orchestration
   - Connects to PostgreSQL for persistence

2. **Harmony** (`harmony-statefulset.yaml`, `harmony-headless-svc.yaml`)
   - GPU workers for training/inference/evaluation
   - Deployed as StatefulSets with headless services
   - Supports multiple **compute pools** - each pool creates a separate StatefulSet with its own config (replicas, GPUs, node selectors)

3. **Sandkasten** (`sandkasten-dpl.yaml`, `sandkasten-svc.yaml`)
   - Sandbox service for custom recipe execution

4. **MLflow** (`mlflow-statefulset.yaml`, `mlflow-svc.yaml`)
   - Optional experiment tracking server

5. **Redis** (`redis-deployment.yaml`, `redis-service.yaml`)
   - Required for caching/session management
   - Can use internal deployment or external Redis

6. **PostgreSQL** (`internal-postgresql-statefulset.yaml`)
   - Optional internal database (disabled by default, external DB recommended)

### Secrets Management

The chart supports two secret patterns:
1. **Inline secrets** - Values provided in `values.yaml`, chart creates K8s Secrets
2. **Existing secrets** - Reference pre-existing secrets via `existingControlPlaneSecret`, `existingHarmonySecret`, `existingRedisSecret`

Key secret files: `control-plane-secret.yaml`, `harmony-secret.yaml`, `redis-secret.yaml`

### Template Helpers (`_helpers.tpl`)

Contains reusable template functions for:
- Component naming (`adaptive.controlPlane.fullname`, `adaptive.harmony.fullname`, etc.)
- Selector labels per component
- Port definitions
- Image URI construction
- Database and Redis URL generation
- OIDC provider TOML formatting

### Monitoring Chart

Deploys Grafana with Loki (log aggregation) and Promtail (log collection). Includes pre-built dashboards in `charts/monitoring/dashboards/`.

## Key Configuration Patterns

### Compute Pools (Harmony)

Multiple GPU worker pools with different configs:
```yaml
harmony:
  computePools:
    - name: training
      replicas: 2
      gpusPerReplica: 8
      capabilities: "TRAINING,EVALUATION"
    - name: inference
      replicas: 4
      gpusPerReplica: 4
      capabilities: "INFERENCE"
      nodeSelector:
        cloud.google.com/gke-accelerator: nvidia-l4
```

### Prometheus Integration

The chart includes Prometheus as a subchart. Adaptive components expose metrics via annotations:
```yaml
prometheus.io/scrape: "adaptive"
prometheus.io/path: /metrics
prometheus.io/port: "50053"  # harmony / "9009" for control-plane
```

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- **lint-test.yml** - Runs on PRs: Artifact Hub lint, chart-testing lint, helm dry-run, kubeconform validation, TOC check
- **publish.yml** - Publishes charts to GHCR OCI registry on release
- **publish-pr.yml** - Builds chart artifacts for PRs
- **helm-diff.yml** - Shows diff of chart changes

## Version Bumping

Chart versions must be bumped when chart content changes (enforced by `ct lint`). Update `version` in:
- `charts/adaptive/Chart.yaml`
- `charts/monitoring/Chart.yaml`
