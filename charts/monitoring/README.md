<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Monitoring Chart](#monitoring-chart)
  - [What's included](#whats-included)
  - [Installation](#installation)
  - [Configuration](#configuration)
    - [Default environment variables](#default-environment-variables)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Monitoring Chart

Optional addon chart that deploys a self-contained [Grafana LGTM](https://github.com/grafana/docker-otel-lgtm) stack (Loki, Grafana, Tempo, Mimir) for observing an Adaptive Engine deployment during development or testing.

This chart is intentionally lightweight: it runs the all-in-one `docker-otel-lgtm` image as a single Deployment so there is nothing external to configure. It is **not** intended for production use.

## What's included

- **Grafana** (port 3000) — dashboards and visualization
- **Prometheus / Mimir** (port 9090) — metrics
- **OpenTelemetry collector** (gRPC 4317, HTTP 4318) — trace and metric ingestion
- **Pyroscope** (port 4040) — continuous profiling
- **Loki** — log aggregation (queried through Grafana)
- Pre-built Grafana dashboards in `dashboards/`

## Installation

```bash
helm install monitoring ./charts/monitoring
```

## Configuration

| Parameter | Description | Default |
|---|---|---|
| `nameOverride` | Override the chart name | `""` |
| `fullnameOverride` | Override the full release name | `""` |
| `image.repository` | Container image | `ghcr.io/grafana/docker-otel-lgtm` |
| `image.tag` | Image tag | `v0.17.1` |
| `image.pullPolicy` | Pull policy | `IfNotPresent` |
| `env` | Environment variables injected into the container (map of name → value) | See below |
| `resources` | CPU/memory requests and limits | `{}` |
| `persistence.enabled` | Enable persistent storage | `false` |
| `persistence.size` | PVC size | `10Gi` |
| `persistence.storageClass` | Storage class | `""` |
| `nodeSelector` | Node selector | `{}` |
| `tolerations` | Tolerations | `[]` |

### Default environment variables

| Variable | Default | Description |
|---|---|---|
| `GF_SECURITY_ADMIN_USER` | `admin` | Grafana admin username |
| `GF_SECURITY_ADMIN_PASSWORD` | `admin` | Grafana admin password |
| `ENABLE_LOGS_GRAFANA` | `true` | Enable Grafana logs |
| `ENABLE_LOGS_LOKI` | `true` | Enable Loki logs |
| `ENABLE_LOGS_PROMETHEUS` | `true` | Enable Prometheus logs |
| `ENABLE_LOGS_TEMPO` | `true` | Enable Tempo logs |
| `ENABLE_LOGS_PYROSCOPE` | `true` | Enable Pyroscope logs |
| `ENABLE_LOGS_OTELCOL` | `true` | Enable OpenTelemetry Collector logs |

Override or add variables via the `env` map:

```yaml
env:
  GF_SECURITY_ADMIN_PASSWORD: my-secret
  ENABLE_LOGS_TEMPO: "false"
```
