# Helm Chart for Adaptive Engine

A Helm Chart to deploy Adaptive Engine.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
  - [Secrets Configuration](#secrets-configuration)
  - [Container Images](#container-images)
  - [GPU Resources](#gpu-resources)
  - [Ingress Configuration](#ingress-configuration)
  - [Using External Secret Management](#using-external-secret-management)
- [Monitoring and Observability](#monitoring-and-observability)
  - [Prometheus Monitoring](#prometheus-monitoring)
  - [MLflow Experiment Tracking](#mlflow-experiment-tracking)
  - [Tensorboard Support](#tensorboard-support)
- [Sandboxing service](#sandboxing-service)
  - [Sandkasten Network Policy (Security)](#sandkasten-network-policy-security)
- [Inference and Autoscaling](#inference-and-autoscaling)
  - [Compute Pools](#compute-pools)
  - [Autoscaling Configuration](#autoscaling-configuration)
  - [External Prometheus for Autoscaling](#external-prometheus-for-autoscaling)
- [Storage and Persistence](#storage-and-persistence)
- [Azure Blob Storage Compatibility](#azure-blob-storage-compatibility)

---

## Compatibility

- Helm chart versions < `0.5.0` are not compatible with adaptive version `0.5.0` or higher.
- **We strongly recommend using the latest helm chart version**


## Prerequisites

[Helm](https://helm.sh) must be installed to use the charts. Helm 3.8.0 or higher is required.

### Required

1. **Kubernetes version**: >= 1.28

2. **NVIDIA GPU Operator**: Installed in the target Kubernetes cluster
   - Installation guide: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html>

### Optional

3. **For Inference Autoscaling**: Adaptive engine supports horizontal pod scaling for inference pools based on QoS metrics (TTFT) and technical metrics (required GPUs vs available GPUs). To support node autoscaling, these requirements must be met:
   - **Cluster Autoscaler** enabled and correctly configured
   - Node pool (or equivalent in your cloud provider) configured to allow scaling GPU nodes
   - Your cloud provider must support on-demand provisioning of GPU instances

4. **Storage Classes**: Required for logs and Prometheus timeseries persistence. See [Storage and Persistence](#storage-and-persistence) for details.

---

## Installation

The charts are published to GitHub Container Registry (GHCR) as OCI artifacts. There are 2 charts available:

- `adaptive` - the main chart to deploy Adaptive Engine
- `monitoring` - an optional addon chart to monitor Adaptive Engine installing Grafana/Loki stack.

### 1. Install the charts from GitHub OCI Registry

```bash
# Install adaptive chart
helm install adaptive oci://ghcr.io/adaptive-ml/adaptive

# Install monitoring chart (optional)
helm install adaptive-monitoring oci://ghcr.io/adaptive-ml/monitoring
```

> **Note:** You can specify the helm chart version by passing the `--version` argument.
>
> To view available chart versions, visit the [GitHub Packages page](https://github.com/orgs/adaptive-ml/packages) for this repository.

### 2. Get the default values.yaml configuration file

```bash
# Pull the chart to inspect values
helm pull oci://ghcr.io/adaptive-ml/adaptive --untar
helm pull oci://ghcr.io/adaptive-ml/monitoring --untar

# Or use helm show (requires Helm 3.8+)
helm show values oci://ghcr.io/adaptive-ml/adaptive > values.yaml
helm show values oci://ghcr.io/adaptive-ml/monitoring > values.monitoring.yaml
```

### 3. Edit the `values.yaml` file

Customize the values file for your environment. See the [Configuration](#configuration) section below for key settings.

### 4. Deploy the chart

```bash
helm install adaptive oci://ghcr.io/adaptive-ml/adaptive -f ./values.yaml
helm install adaptive-monitoring oci://ghcr.io/adaptive-ml/monitoring -f ./values.monitoring.yaml
```

If you deploy the addon `adaptive-monitoring` chart, make sure to override the default value of `grafana.proxy.domain` in the `values.monitoring.yaml` file; it must match the value of your ingress domain (`controlPlane.rootUrl`) for Adaptive Engine (as a fully qualified domain name, no scheme). Once deployed, you will be able to access the Grafana dashboard for logs monitoring at your ingress domain + `/monitoring/explore`.

---

## Configuration

See the full `charts/adaptive/values.yaml` file for all available configuration options.

### Secrets Configuration

The chart supports two approaches for managing secrets:

#### Option 1: Inline Secrets (Default)

Provide secret values directly in your values file, and the chart will create Kubernetes secrets:

```yaml
secrets:
  # S3 bucket for model registry
  modelRegistryUrl: "s3://bucket-name/model_registry"
  # Use same bucket as above and can use a different prefix
  sharedDirectoryUrl: "s3://bucket-name/shared"

  # Postgres database connection string
  dbUrl: "postgres://username:password@db_adress:5432/db_name"
  # Secret used to sign cookies. Must be the same on all servers of a cluster and >= 64 chars
  cookiesSecret: "change-me-secret-db40431e-c2fd-48a6-acd6-854232c2ed94-01dd4d01-dr7b-4315" # Must be >= 64 chars

  auth:
    oidc:
      providers:
        # Name of your OpenId provider displayed in the ui
        - name: "Google"
          # Key of your provider, the callback url will be '<rootUrl>/api/v1/auth/login/<key>/callback'
          key: "google"
          issuer_url: "https://accounts.google.com" # openid connect issuer url
          client_id: "replace_client_id" # client id
          client_secret: "replace_client_secret" # client_secret, optional
          scopes: ["email", "profile"] # scopes required for auth, requires email and profile
          # true if your provider supports pkce (recommended)
          pkce: true
          # if true, user account will be created if it does not exist
          allow_sign_up: true
```

#### Option 2: Reference Existing Secrets

If you manage secrets externally (using External Secrets Operator, Sealed Secrets, manual provisioning, etc.), you can reference existing secrets instead:

```yaml
secrets:
  # Reference existing Kubernetes secrets
  existingControlPlaneSecret: "my-control-plane-secret"
  existingHarmonySecret: "my-harmony-secret"
  existingRedisSecret: "my-redis-secret"
  
  # IMPORTANT: Clear inline values to avoid validation errors
  dbUrl: ""
  cookiesSecret: ""
  modelRegistryUrl: ""
  sharedDirectoryUrl: ""
  auth:
    oidc:
      providers: []
```

> **Note:** The chart validates that you don't accidentally provide both an `existingSecret` reference and inline values. If both are detected, Helm will fail with a clear error message to prevent configuration surprises. Make sure to clear/remove inline secret values when using external secrets.

**Required keys for existing secrets:**

> **Note:** Secret keys use the same names as the values.yaml field names for simplicity. The chart handles mapping them to the appropriate environment variables internally.

The `existingControlPlaneSecret` must contain these keys:
- `dbUrl` - Database connection string
- `cookiesSecret` - Cookie signing secret (>= 64 chars)
- `oidcProviders` - OIDC configuration in TOML array format (example below):
  ```toml
  [{
    key="google",
    name="Google",
    issuer_url="https://accounts.google.com",
    client_id="your_client_id",
    client_secret="your_client_secret",
    scopes=["email","profile"],
    pkce=true,
    allow_sign_up=true
  }]
  ```

The `existingHarmonySecret` must contain these keys:
- `modelRegistryUrl` - S3 bucket URL for model registry
- `sharedDirectoryUrl` - S3 bucket URL for shared directory

The `existingRedisSecret` must contain this key:
- `redisUrl` - Redis connection URL (auto-generated from `redis.auth.*` if using built-in Redis)

For detailed examples of using external secret management tools, see the [Using External Secret Management](#using-external-secret-management) section below.

### Container Images

Configure the Adaptive container registry and image tags:

```yaml
# Adaptive Registry you have been granted access to
containerRegistry: <aws_account_id>.dkr.ecr.<region>.amazonaws.com

harmony:
  image:
    repository: adaptive-repository # Adaptive Repository you have been granted access to
    tag: harmony:latest # Harmony image tag

controlPlane:
  image:
    repository: adaptive-repository # Adaptive Repository you have been granted access to
    tag: control-plane:latest # Control plane image tag
```

### GPU Resources

Configure GPU allocation for Harmony pods:

```yaml
harmony:
  # Should be equal to, or a divisor of the # of GPUs on each node
  gpusPerReplica: 8
```

### Ingress Configuration

The Adaptive Helm chart supports configuring a Kubernetes Ingress resource to expose the Control Plane API service and Adaptive UI externally. By default, ingress is disabled.

#### Enabling Ingress

To enable ingress, set `ingress.enabled=true` in your values file:

```yaml
ingress:
  enabled: true
  className: "nginx"  # Optional: specify your ingress class (e.g., nginx, traefik, alb)
  hosts:
    - host: adaptive.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
```

#### Configuration Options

**Ingress Class**

Specify the ingress controller class to use:

```yaml
ingress:
  className: "nginx"  # or "traefik", "alb", etc.
```

**Custom Annotations**

Add annotations for your specific ingress controller:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
```

**TLS/SSL Configuration**

Enable HTTPS with TLS:

```yaml
ingress:
  tls:
    - secretName: adaptive-tls-secret
      hosts:
        - adaptive.example.com
```

**Note:** Make sure your `controlPlane.rootUrl` matches your ingress host configuration:

```yaml
controlPlane:
  rootUrl: "https://adaptive.example.com"
```

#### Complete Ingress Example

Here's a complete example for an NGINX ingress controller with TLS:

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
  hosts:
    - host: adaptive.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: adaptive-tls-secret
      hosts:
        - adaptive.example.com

controlPlane:
  rootUrl: "https://adaptive.example.com"
  servicePort: 80
```

### Using External Secret Management

The chart does not include any opinionated secret management integration. You can use any secret management solution you prefer (External Secrets Operator, Sealed Secrets, etc.) and reference those secrets in your Helm values.

#### Example: Using External Secrets Operator

If you're using [External Secrets Operator](https://external-secrets.io/latest/), follow these steps:

**1. Install External Secrets Operator** in your cluster ([installation guide](https://external-secrets.io/latest/introduction/getting-started/))

**2. Create a SecretStore** for your secret backend:

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: default
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        # Configure authentication to your secret backend
```

**3. Create ExternalSecret resources** for Control Plane, Harmony, and Redis:

> **Note:** Secret keys match the values.yaml field names for simplicity (e.g., `dbUrl`, `cookiesSecret`). The chart handles environment variable mapping internally.

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: adaptive-control-plane-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: adaptive-control-plane-secret
    creationPolicy: Owner
  data:
    - secretKey: dbUrl
      remoteRef:
        key: adaptive/db-url
    - secretKey: cookiesSecret
      remoteRef:
        key: adaptive/cookies-secret
    - secretKey: oidcProviders  # Value must be in TOML array format
      remoteRef:
        key: adaptive/oidc-providers  # Store the TOML array in your secret backend
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: adaptive-harmony-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: adaptive-harmony-secret
    creationPolicy: Owner
  data:
    - secretKey: modelRegistryUrl
      remoteRef:
        key: adaptive/model-registry-url
    - secretKey: sharedDirectoryUrl
      remoteRef:
        key: adaptive/shared-directory-url
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: adaptive-redis-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: adaptive-redis-secret
    creationPolicy: Owner
  data:
    - secretKey: redisUrl
      remoteRef:
        key: adaptive/redis-url
```

**4. Reference the secrets** in your Helm values:

```yaml
secrets:
  existingControlPlaneSecret: "adaptive-control-plane-secret"
  existingHarmonySecret: "adaptive-harmony-secret"
  existingRedisSecret: "adaptive-redis-secret"
  
  # Clear inline values to use external secrets
  dbUrl: ""
  cookiesSecret: ""
  modelRegistryUrl: ""
  sharedDirectoryUrl: ""
  auth:
    oidc:
      providers: []
```

**5. Deploy the Helm chart:**

```bash
helm install adaptive oci://ghcr.io/adaptive-ml/adaptive -f values.yaml
```

#### Example: Using Sealed Secrets

If you're using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets):

**1. Create your secrets** and seal them:

> **Note:** Secret keys match the values.yaml field names (e.g., `dbUrl`, `cookiesSecret`) for simplicity.

```bash
# Create control plane secret
# Note: oidcProviders must be in TOML array format
kubectl create secret generic adaptive-control-plane-secret \
  --from-literal=dbUrl="postgres://..." \
  --from-literal=cookiesSecret="..." \
  --from-literal=oidcProviders='[{key=google,name=Google,issuer_url="https://accounts.google.com",client_id="...",client_secret="...",scopes=["email","profile"],pkce=true,allow_sign_up=true},]' \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-control-plane-secret.yaml

# Create harmony secret
kubectl create secret generic adaptive-harmony-secret \
  --from-literal=modelRegistryUrl="s3://..." \
  --from-literal=sharedDirectoryUrl="s3://..." \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-harmony-secret.yaml

# Create redis secret
kubectl create secret generic adaptive-redis-secret \
  --from-literal=redisUrl="redis://..." \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-redis-secret.yaml

# Apply the sealed secrets
kubectl apply -f sealed-control-plane-secret.yaml
kubectl apply -f sealed-harmony-secret.yaml
kubectl apply -f sealed-redis-secret.yaml
```

**2. Reference the secrets** in your Helm values as shown above.

#### Example: Manual Secret Creation

You can also create secrets manually:

> **Note:** Secret keys match the values.yaml field names (e.g., `dbUrl`, `cookiesSecret`) for simplicity.

```bash
# Control plane secret
# Note: oidcProviders must be in TOML array format
kubectl create secret generic adaptive-control-plane-secret \
  --from-literal=dbUrl="postgres://username:password@host:5432/db" \
  --from-literal=cookiesSecret="your-64-char-secret" \
  --from-literal=oidcProviders='[{key="google",name="Google",issuer_url="https://accounts.google.com",client_id="your_client_id",client_secret="your_client_secret",scopes=["email","profile"],pkce=true,allow_sign_up=true}]'

# Harmony secret
kubectl create secret generic adaptive-harmony-secret \
  --from-literal=modelRegistryUrl="s3://bucket/models" \
  --from-literal=sharedDirectoryUrl="s3://bucket/shared"

# Redis secret
kubectl create secret generic adaptive-redis-secret \
  --from-literal=redisUrl="redis://redis-host:6379"
```

Then reference these secrets in your values file as shown above

---

## Monitoring and Observability

### Prometheus Monitoring

This Helm chart includes Prometheus as a dependency for metrics collection and monitoring. Prometheus is used to:

- Collect metrics from Adaptive Engine components (Control Plane and Harmony)
- Power the autoscaling feature by providing TTFT (Time To First Token) timeout metrics to KEDA
- Monitor system health and performance

#### Enabling/Disabling Prometheus

By default, Prometheus is **enabled**. You can disable it by setting:

```yaml
prometheus:
  enabled: false  # Set to false to disable the embedded Prometheus subchart
```

**Important:** If you enable inference autoscaling (`autoscaling.enabled=true`), Prometheus **must** be enabled (or an external Prometheus instance must be configured). The autoscaler relies on Prometheus metrics to make scaling decisions based on TTFT timeout rates.

#### Configuring Prometheus

The chart uses the [Prometheus Community Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus) as a subchart. You can customize Prometheus settings under the `prometheus` key in your values file:

```yaml
prometheus:
  enabled: true
  
  server:
    # Prometheus data retention period
    retention: "30d"
    
    # Number of Prometheus replicas for high availability
    replicaCount: 2
    
    # Persistence configuration
    persistentVolume:
      enabled: true
      size: 10Gi
      storageClass: "your-storage-class"
```

#### Metrics Collection

Adaptive Engine components expose metrics that are automatically scraped by Prometheus:

- **Harmony pods**: Expose metrics on port `50053` at `/metrics`
- **Control Plane**: Exposes metrics on port `9009` at `/metrics`

Pods are discovered automatically using the annotation-based scraping configuration:

```yaml
podAnnotations:
  prometheus.io/scrape: "adaptive"
  prometheus.io/path: /metrics
  prometheus.io/port: "50053"  # or "9009" for Control Plane
```

### MLflow Experiment Tracking

Adaptive Engine supports MLflow for experiment tracking and model versioning. When enabled, training jobs can log metrics, parameters, and artifacts to a dedicated MLflow tracking server.

By default, MLflow is **enabled** and takes priority over Tensorboard if both are enabled.

The chart supports three MLflow configurations:

1. **Internal MLflow** (default) - Deploys an MLflow server within the cluster
2. **External MLflow** - Uses an existing external MLflow server
3. **Disabled** - No MLflow tracking

#### Option 1: Internal MLflow (Default)

Deploy an MLflow server within your Kubernetes cluster:

```yaml
mlflow:
  enabled: true
  external:
    enabled: false  # Use internal deployment
  
  imageUri: ghcr.io/mlflow/mlflow:v3.1.1
  replicaCount: 1
  workers: 4  # Recommended: 2-4 workers per CPU core
```

**Storage Configuration:**

MLflow uses the `mlflow-artifacts:/` URI scheme, which means artifacts are sent via HTTP to the server and stored server-side. This allows multiple training partitions to upload artifacts without requiring shared storage.

```yaml
mlflow:
  backendStoreUri: sqlite:///mlflow-storage/mlflow.db
  defaultArtifactRoot: mlflow-artifacts:/
  serveArtifacts: true
  
  # Storage for MLflow database and artifacts
  volumes:
    - name: mlflow-storage
      emptyDir: {}  # Default: ephemeral storage
```

**Persistent Storage Example:**

To persist MLflow data across restarts, configure a persistent volume:

```yaml
mlflow:
  volumes:
    - name: mlflow-storage
      hostPath:
        path: /mnt/nfs/mlflow
        type: Directory
  
  volumeMounts:
    - name: mlflow-storage
      mountPath: /mlflow-storage
```

#### Option 2: External MLflow

This is useful when:

- You have a centralized MLflow server shared across multiple teams or projects
- You want to use a managed MLflow service
- You prefer to manage MLflow separately from the Adaptive deployment

```yaml
mlflow:
  enabled: true
  external:
    enabled: true
    url: "http://mlflow.example.com:5000"  # URL of your external MLflow server
```

#### Option 3: Disable MLflow

To disable MLflow tracking entirely:

```yaml
mlflow:
  enabled: false
```

When MLflow is disabled, you can optionally enable Tensorboard for logging (see [Tensorboard Support](#tensorboard-support)).

### Tensorboard Support

To track training job progress with Tensorboard, you can enable Tensorboard support. This will start a Tensorboard server as a sidecar container. By default, the logs are not persisted and are saved in a temporary directory.

**Note:** MLflow takes priority over Tensorboard if both are enabled.

```yaml
tensorboard:
  enabled: true  # default is false
  imageUri: tensorflow/tensorflow:latest
  
  # Use the persistent volume config to enable log saving across restarts
  persistentVolume:
    enabled: true
    storageClass: "your-storage-class"
  
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 500m
      memory: 1Gi
```

---

## Sandboxing Service (Sandkasten)

> **Added in:** Helm chart version `0.12.0`

Sandkasten executes custom recipes and arbitrary code. **Security is enforced by default** and cannot be disabled.

### Built-in Security (Always Active)

✅ **Network Policy**: Always enabled, it protects against *reverse shells, metadata service exploitation, data exfiltration, lateral movement*

### Network Policy Requirements

**Production/Enterprise:** All major platforms support Network Policies (EKS, AKS, GKE, OpenShift, Rancher, kubeadm with Calico/Cilium)

**Local Dev:** Docker Desktop and basic Minikube don't support Network Policies. Use: `minikube start --cni=calico`

**Check support:** `kubectl api-resources | grep networkpolicies`

### Configuration

**Default (secure, no changes needed):**

```yaml
sandkasten:
  replicaCount: 2
  servicePort: 3005
  
  serviceAccount:
    create: true       # Dedicated SA
    automount: false   # No K8s API access
  
  networkPolicy:
    # Network policy always enabled (cannot be disabled)
    # Blocks: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.169.254
    additionalBlockedCIDRs: []  # Optional: block additional networks
```

**Only if Sandkasten needs internal service access (rare):**

> To allow access to a specific internal network (e.g., `10.50.0.0/16`), you must customize the NetworkPolicy resource.
> This can be done by forking the chart and editing `sandkasten-netpol.yaml`, or by applying your own NetworkPolicy resource.
> Example (custom NetworkPolicy egress rule):

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 10.50.0.0/16
    ports:
      - protocol: TCP
        port: <your-port>
### Testing Network Policy

```bash
# Should work: External internet
kubectl exec -n <ns> deploy/<sandkasten> -- curl https://google.com

# Should fail: Metadata service
kubectl exec -n <ns> deploy/<sandkasten> -- curl http://169.254.169.254 --max-time 5

# Should work: Harmony service
kubectl exec -n <ns> deploy/<sandkasten> -- curl http://<harmony-svc>:80
```

---

## Inference and Autoscaling

### Compute Pools

You can define Harmony deployment groups dedicated to inference tasks:

```yaml
harmony:
  computePool:
     - name: "Pool-A"
       minReplicaCount: 1
       maxReplicaCount: 5
     - name: "Pool-B"
       minReplicaCount: 2
       maxReplicaCount: 10
       nodeSelector:
         gpu-type: a100
```

Each compute pool can have its own configuration. Any values not specified will be inherited from the main `harmony` section.

### Autoscaling Configuration

By default, `autoscaling.enabled` is set to `false`. When disabled, the `maxReplicaCount` is ignored and each pool has a fixed number of replicas equal to `minReplicaCount`.

When `autoscaling.enabled=true`, the inference autoscaling is activated using **KEDA** (Kubernetes Event-Driven Autoscaling). The autoscaler can scale each inference pool up to its configured `maxReplicaCount` based on metrics collected from Prometheus.

**Basic Configuration:**

```yaml
autoscaling:
  enabled: true
  coolDownPeriodSeconds: 180  # Duration to wait before scaling down pods
  ttftTimeoutThreshold: 0.1   # Proportion of timed-out requests that triggers scale-out
```

**How it works:**
- KEDA monitors TTFT (Time To First Token) timeout metrics from Prometheus
- When the timeout rate exceeds `ttftTimeoutThreshold`, the autoscaler triggers scale-out
- After scaling, the autoscaler waits `coolDownPeriodSeconds` before considering scale-down

### External Prometheus for Autoscaling

By default, the autoscaler uses the embedded Prometheus instance (`http://adaptive-prometheus`). If you have an external Prometheus instance that collects metrics from Adaptive Engine, you can configure the autoscaler to use it instead:

```yaml
autoscaling:
  enabled: true
  externalPrometheusEndpoint: "your-external-prometheus-http(s)-endpoint"
```

**Example with external Prometheus:**

```yaml
autoscaling:
  enabled: true
  externalPrometheusEndpoint: "http://prometheus-server.monitoring.svc.cluster.local"
  coolDownPeriodSeconds: 180
  ttftTimeoutThreshold: 0.1
```

This is useful when:
- You have an external Prometheus instance for your cluster
- You want to disable the embedded Prometheus (`prometheus.enabled=false`) and use your own
- You need to query metrics from a Prometheus instance in a different namespace

---

## Storage and Persistence

### Monitoring Stack

For the **monitoring** stack helm chart: by default, logs and Grafana data are not persisted. You should enable persistence by setting:

```yaml
grafana:
  enablePersistence: true
  storageClass: "your-storage-class-name"
```

### Adaptive Chart (Prometheus)

For the **adaptive** helm chart: Prometheus may require metrics data to be persisted. By default, `prometheus.server.persistentVolume.enabled=false`. When enabling persistence, you must specify the storage class name:

```yaml
prometheus:
  server:
    persistentVolume:
      enabled: true
      size: 10Gi
      storageClass: "your-storage-class-name"
```

---

## Azure Blob Storage Compatibility

The Adaptive Helm chart supports any S3-compliant storage service, and Azure Blob Storage out-of-the-box via [s3proxy](https://github.com/gaul/s3proxy). The default is S3.

To enable Azure Blob Storage, set this override in the helm values:

```yaml
s3proxy:
  enabled: true
  azure:
    storageAccount:
      name: your_azure_account_name
      accessKey: your_azure_access_key
```
