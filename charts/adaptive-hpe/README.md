# Adaptive HPE Helm Chart

This Helm chart combines the Adaptive Engine with monitoring capabilities and adds Istio integration for advanced traffic management.

## Prerequisites

- Kubernetes 1.26 or later
- Helm 3.x
- Istio installed in the cluster (if using Istio features)

## Installation

```bash
# Add the repository
helm repo add adaptive-ml https://adaptive-ml.github.io/helm-charts

# Install the chart
helm install my-adaptive-hpe adaptive-ml/adaptive-hpe
```

## Configuration

The following table lists the configurable parameters of the adaptive-hpe chart and their default values.

### Istio Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `istio.enabled` | Enable Istio integration | `true` |
| `istio.host` | Host name for the VirtualService | `""` (defaults to `<release-name>.<namespace>`) |
| `istio.gateway` | Istio Gateway to use | `""` |

### Adaptive Configuration

All configuration options from the adaptive chart are available under the `adaptive` key.

### Monitoring Configuration

All configuration options from the monitoring chart are available under the `monitoring` key.

## Usage

1. Configure the values in a custom values file:

```yaml
istio:
  enabled: true
  host: "my-adaptive.example.com"
  gateway: "my-gateway"

adaptive:
  # Adaptive-specific configuration
  service:
    port: 8080

monitoring:
  # Monitoring-specific configuration
  service:
    port: 9090
```

2. Install the chart with your custom values:

```bash
helm install my-adaptive-hpe adaptive-ml/adaptive-hpe -f custom-values.yaml
```

## License

This chart is licensed under the Apache License 2.0. 