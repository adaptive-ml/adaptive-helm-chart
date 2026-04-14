# Helm Chart for Adaptive Engine

A Helm Chart to deploy Adaptive Engine.

## Table of Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Compatibility](#compatibility)
- [Prerequisites](#prerequisites)
  - [Required](#required)
  - [Optional](#optional)
- [Installation](#installation)
  - [1. Install the chart from GitHub OCI Registry](#1-install-the-chart-from-github-oci-registry)
  - [2. Get the default values.yaml configuration file](#2-get-the-default-valuesyaml-configuration-file)
  - [3. Edit the `values.yaml` file](#3-edit-the-valuesyaml-file)
  - [4. Deploy the chart](#4-deploy-the-chart)
- [Configuration](#configuration)
  - [Secrets Configuration](#secrets-configuration)
  - [Redis Configuration](#redis-configuration)
  - [MinIO Object Storage (Optional)](#minio-object-storage-optional)
  - [S3 Proxy for Azure Blob Storage (Optional)](#s3-proxy-for-azure-blob-storage-optional)
  - [ClickHouse Analytics Database (Optional)](#clickhouse-analytics-database-optional)
  - [Container Images](#container-images)
  - [GPU Resources](#gpu-resources)
  - [Ingress Configuration](#ingress-configuration)
  - [Using External Secret Management](#using-external-secret-management)
- [Monitoring and Observability](#monitoring-and-observability)
  - [LGTM Stack (Grafana, Loki, Tempo, Mimir, Pyroscope)](#lgtm-stack-grafana-loki-tempo-mimir-pyroscope)
  - [OpenTelemetry Collector](#opentelemetry-collector)
  - [MLflow Experiment Tracking](#mlflow-experiment-tracking)
- [Sandboxing service](#sandboxing-service)
- [Compute Pools](#compute-pools)
  - [Per-Pool Node Selectors](#per-pool-node-selectors)
- [Storage and Persistence](#storage-and-persistence)
  - [LGTM Stack](#lgtm-stack)
- [Extra Objects](#extra-objects)
- [Cloud specific information](#cloud-specific-information)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Compatibility

- Helm chart versions < `0.34` are not compatible with adaptive version `0.13.0` or higher.
- Helm chart versions < `0.5.0` are not compatible with adaptive version `0.5.0` or higher.
- **We strongly recommend using the latest helm chart version**


## Prerequisites

[Helm](https://helm.sh) must be installed to use the charts. Helm 3.8.0 or higher is required.

### Required

1. **Kubernetes version**: >= 1.28

2. **NVIDIA GPU Operator**: Installed in the target Kubernetes cluster
   - Installation guide: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html>

### Optional

3. **Storage Classes**: Required for logs persistence. See [Storage and Persistence](#storage-and-persistence) for details.

---

## Installation

The chart is published to GitHub Container Registry (GHCR) as an OCI artifact.

### 1. Install the chart from GitHub OCI Registry

```bash
helm install adaptive oci://ghcr.io/adaptive-ml/adaptive
```

> **Note:** You can specify the helm chart version by passing the `--version` argument.
>
> To view available chart versions, visit the [GitHub Packages page](https://github.com/orgs/adaptive-ml/packages) for this repository.

### 2. Get the default values.yaml configuration file

```bash
# Pull the chart to inspect values
helm pull oci://ghcr.io/adaptive-ml/adaptive --untar

# Or use helm show (requires Helm 3.8+)
helm show values oci://ghcr.io/adaptive-ml/adaptive > values.yaml
```

### 3. Edit the `values.yaml` file

Customize the values file for your environment. See the [Configuration](#configuration) section below for key settings.

### 4. Deploy the chart

```bash
helm install adaptive oci://ghcr.io/adaptive-ml/adaptive -f ./values.yaml
```

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

  # S3 credentials (injected as env vars on control-plane, harmony, and sandkasten pods)
  s3Creds:
    AWS_ACCESS_KEY_ID: "AKxxx"
    AWS_SECRET_ACCESS_KEY: "xxx"
    AWS_REGION: "us-west-2"
    AWS_DEFAULT_REGION: "us-west-2"

  # Postgres database connection configuration
  db:
    username: "username"
    password: "password"
    host: "db_address:5432"  # Host and port
    database: "db_name"
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
  existingS3CredsSecret: "my-s3-creds-secret"
  existingClickHouseSecret: "my-clickhouse-secret"  # Only needed when clickhouse.enabled=true

  # IMPORTANT: Clear inline values to avoid validation errors
  # db, cookiesSecret, modelRegistryUrl, sharedDirectoryUrl, s3Creds, and auth should not be set
```

> **Note:** The chart validates that you don't accidentally provide both an `existingSecret` reference and inline values. If both are detected, Helm will fail with a clear error message to prevent configuration surprises. Make sure to clear/remove inline secret values when using external secrets.

**Required keys for existing secrets:**

> **Note:** Secret keys use the same names as the values.yaml field names for simplicity. The chart handles mapping them to the appropriate environment variables internally.

The `existingControlPlaneSecret` must contain these keys:
- `dbUsername` - Database username
- `dbPassword` - Database password
- `dbHost` - Database host and port (e.g., `db_address:5432`)
- `dbName` - Database name
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

The `existingS3CredsSecret` can contain any keys — all keys are injected as environment variables on control-plane, harmony, and sandkasten pods. Typical keys include:
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key
- `AWS_DEFAULT_REGION` - AWS region
- `AWS_ENDPOINT_URL_S3` - Custom S3 endpoint (for S3-compatible storage)
- `S3_FORCE_PATH_STYLE` - Set to `"true"` for path-style S3 access

The `existingRedisSecret` must contain this key:
- `redisUrl` - Redis connection URL (format: `redis://[username:password@]host:port`)

The `existingClickHouseSecret` (only when `clickhouse.enabled=true`) must contain these keys:
- `clickhouseUrl` - ClickHouse HTTP URL (e.g., `http://clickhouse:8123`)
- `clickhouseUsername` - ClickHouse username
- `clickhousePassword` - ClickHouse password
- `clickhouseDatabase` - ClickHouse database name

> **Note:** When using `existingRedisSecret`, you should typically set `redis.install.enabled` to `false` (no internal Redis deployment). If you want to deploy Redis internally and manage the secret externally, set `redis.install.enabled=true` **without** specifying `existingRedisSecret`, and manage the Redis authentication values separately. See [Redis Configuration](#redis-configuration) for more details.

For detailed examples of using external secret management tools, see the [Using External Secret Management](#using-external-secret-management) section below.

### Redis Configuration

Adaptive Engine requires Redis for caching and session management. The chart supports three Redis deployment options:

1. **Internal Redis** (default) - Deploys Redis within the cluster
2. **External Redis** - Uses an existing external Redis instance
3. **Existing Secret** - References a pre-existing Kubernetes secret containing the Redis URL

#### Option 1: Internal Redis (Default)

By default, the chart deploys a Redis instance within your Kubernetes cluster:

```yaml
redis:
  install:
    enabled: true  # Deploy Redis in-cluster (default)

  # Redis image configuration
  image:
    repository: redis
    tag: "7.4.7-alpine"
    pullPolicy: IfNotPresent

  port: 6379

  # Optional: Redis authentication
  auth:
    username: ""  # Leave empty for no username
    password: ""  # Leave empty for no password

  # Resource limits
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 500m
      memory: 512Mi
```

**Note:** The chart currently manages Redis 7.  We recommend using an external managed Redis service for production deployments.

#### Option 2: External Redis

To use an external Redis instance (e.g., AWS ElastiCache, Azure Cache for Redis, Google Cloud Memorystore, or a self-managed Redis):

```yaml
redis:
  install:
    enabled: false  # Disable in-cluster Redis deployment

  # External Redis endpoint
  external:
    url: "redis://redis.example.com:6379"
    # Or with authentication:
    # url: "redis://username:password@redis.example.com:6379"
```

**Important:** When `install.enabled=false`, you **must** provide `redis.external.url`. The chart will validate this requirement and fail with a clear error if missing.

#### Option 3: Existing Secret

If you manage Redis secrets externally (using External Secrets Operator, Sealed Secrets, etc.), you can reference an existing Kubernetes secret:

```yaml
secrets:
  existingRedisSecret: "my-redis-secret"

redis:
  install:
    enabled: false  # Can be true or false when using existingRedisSecret
    # If true: Redis will be deployed but will use the existing secret for connection
    # If false: No Redis deployed, uses existing secret only
```

The existing secret must contain a `redisUrl` key with the Redis connection URL.

**Note:** When using `existingRedisSecret`, you cannot provide inline `redis.auth.*` values. The chart validates this to prevent configuration conflicts.

#### Configuration Options

**Mutual Exclusivity:**

- `redis.install.enabled=true` and `redis.external.url` cannot both be set (unless using `existingRedisSecret`)
- `redis.install.enabled=false` requires `redis.external.url` to be provided
- `existingRedisSecret` cannot be used with inline `redis.auth.*` values

**Customization:**

You can customize the internal Redis deployment with:

```yaml
redis:
  install:
    enabled: true

  # Pod annotations and labels
  podAnnotations: {}
  podLabels: {}

  # Node placement
  nodeSelector: {}
  tolerations: []

  # Additional environment variables
  extraEnvVars: {}
```

### MinIO Object Storage (Optional)

The chart can deploy an internal [MinIO](https://min.io/) S3-compatible object storage instance using the [Bitnami MinIO subchart](https://github.com/bitnami/charts/tree/main/bitnami/minio). This is intended for **testing and development** environments where you don't have access to an external S3-compatible storage service (e.g., AWS S3, Google Cloud Storage).

> **Warning:** MinIO is **not recommended for production**. For production deployments, use an external managed S3 service and configure `secrets.modelRegistryUrl` and `secrets.sharedDirectoryUrl` directly.

#### Enabling MinIO

```yaml
minio:
  enabled: true

  auth:
    rootUser: adaptive
    rootPassword: "your-secure-password"  # REQUIRED when enabled=true
```

When MinIO is enabled, the chart automatically:

- Deploys a MinIO instance in the cluster
- Creates a default bucket (configurable via `minio.bucketName`, defaults to `adaptive`)
- Sets `secrets.modelRegistryUrl` to `s3://<bucketName>/model_registry`
- Sets `secrets.sharedDirectoryUrl` to `s3://<bucketName>/shared`
- Populates the `s3Creds` secret with MinIO credentials and endpoint (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `AWS_ENDPOINT_URL_S3`, `S3_FORCE_PATH_STYLE`)

You do **not** need to set `secrets.modelRegistryUrl`, `secrets.sharedDirectoryUrl`, or `secrets.s3Creds` when MinIO is enabled. Any values you provide in `secrets.s3Creds` take precedence over the auto-populated MinIO defaults.

#### Configuration

```yaml
minio:
  enabled: false  # Set to true to deploy MinIO

  # Authentication (required when enabled)
  auth:
    rootUser: adaptive
    rootPassword: ""  # REQUIRED when enabled=true

  # URL scheme for the MinIO endpoint (default: "http")
  # Override to "https" if TLS is configured on the MinIO service
  scheme: "http"

  # Bucket name for model registry and shared directory
  bucketName: adaptive

  # Bucket created automatically at MinIO startup
  # IMPORTANT: Must match minio.bucketName
  defaultBuckets: "adaptive"

  # Service configuration
  service:
    type: ClusterIP
    ports:
      api: 9000

  # Persistence (recommended for data durability)
  persistence:
    enabled: false        # Set to true to persist data across restarts
    storageClass: ""      # Use default storage class if empty
    size: 20Gi
    accessModes:
      - ReadWriteOnce

  # Resources
  resources:
    limits:
      cpu: 4000m
      memory: 16Gi
    requests:
      cpu: 4000m
      memory: 16Gi

  # MinIO web console
  console:
    enabled: true
```

For the full list of Bitnami MinIO subchart options, see the [Bitnami MinIO chart documentation](https://github.com/bitnami/charts/tree/main/bitnami/minio).

### S3 Proxy for Azure Blob Storage (Optional)

When running Adaptive Engine on **Azure**, you can use [s3proxy](https://github.com/gaul/s3proxy) to expose Azure Blob Storage through an S3-compatible API. The chart deploys an s3proxy instance inside the cluster that translates S3 API calls from Adaptive components into Azure Blob Storage operations.

> **Note:** This option is only for Azure Blob Storage. For AWS S3, configure `secrets.s3Creds` directly. For self-hosted S3-compatible storage, use `minio.enabled` instead.

> **Important:** `s3proxy.enabled` and `minio.enabled` are mutually exclusive — the chart will fail if both are set to `true`.

#### How it works

When `s3proxy.enabled=true`, the chart:

- Deploys an s3proxy Deployment and Service in the cluster
- Creates a secret with Azure Blob Storage credentials for the s3proxy pod (unless `secrets.existingS3ProxySecret` is set)
- Auto-populates the `s3Creds` secret with S3 credentials pointing to the s3proxy endpoint (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `AWS_ENDPOINT_URL_S3`, `S3_FORCE_PATH_STYLE`)
- Sets `modelRegistryUrl` to `s3://<containerName>/model_registry` and `sharedDirectoryUrl` to `s3://<containerName>/shared`
- Configures the Control Plane with the s3proxy endpoint for shared directory access

You do **not** need to set `secrets.modelRegistryUrl`, `secrets.sharedDirectoryUrl`, or `secrets.s3Creds` when s3proxy is enabled. Any values you provide in `secrets.s3Creds` take precedence over the auto-populated defaults.

#### Prerequisites

The Azure Blob Storage container specified in `s3proxy.azure.containerName` must already exist in your storage account before deploying. The chart does not create it automatically.

#### Option 1: Inline Credentials

Provide Azure credentials directly in your values file:

```yaml
s3proxy:
  enabled: true

  azure:
    storageAccountName: "mystorageaccount"       # REQUIRED
    storageAccountKey: "base64-encoded-key..."    # REQUIRED
    containerName: adaptive                       # Must exist in the storage account
```

#### Option 2: Existing Secret

If you manage secrets externally (using External Secrets Operator, Sealed Secrets, Azure Key Vault, etc.), you can reference a pre-existing Kubernetes secret instead of providing inline Azure credentials:

```yaml
secrets:
  existingS3ProxySecret: "my-s3proxy-secret"

s3proxy:
  enabled: true

  azure:
    containerName: adaptive  # Still needed — controls the S3 bucket URLs
```

When `secrets.existingS3ProxySecret` is set, the chart does **not** create the s3proxy secret — it mounts the referenced secret on the s3proxy pod instead. The existing secret must contain these keys:

| Key | Description |
|-----|-------------|
| `JCLOUDS_PROVIDER` | Backend provider (use `azureblob-sdk`) |
| `JCLOUDS_IDENTITY` | Azure storage account name |
| `JCLOUDS_CREDENTIAL` | Azure storage account key |
| `JCLOUDS_ENDPOINT` | Azure Blob endpoint (e.g., `https://myaccount.blob.core.windows.net`) |

> **Note:** S3 authentication between Adaptive components and s3proxy uses fixed credentials managed by the chart (`S3PROXY_IDENTITY`, `S3PROXY_CREDENTIAL`, etc.). These are injected as env vars on the s3proxy pod and into the `s3Creds` secret automatically — do not include them in your existing secret.

#### Configuration

```yaml
secrets:
  existingS3ProxySecret: ""  # Reference a pre-existing secret for s3proxy (optional)

s3proxy:
  enabled: false  # Set to true to deploy s3proxy

  image:
    repository: andrewgaul/s3proxy
    tag: "sha-97e07e9"
    pullPolicy: IfNotPresent

  # Azure Blob Storage backend (ignored when secrets.existingS3ProxySecret is set)
  azure:
    storageAccountName: ""  # REQUIRED when existingS3ProxySecret is not set
    storageAccountKey: ""   # REQUIRED when existingS3ProxySecret is not set
    endpoint: ""            # Optional (defaults to https://<storageAccountName>.blob.core.windows.net)
    containerName: adaptive # Azure Blob container name (must already exist)

  # Service configuration
  service:
    type: ClusterIP
    port: 80

  # Resources
  resources: {}
  podAnnotations: {}
  podLabels: {}
  nodeSelector: {}
  tolerations: []
```

#### Custom Azure Endpoint

To use a custom Azure Blob Storage endpoint (e.g., Azure Government or Azure China):

```yaml
s3proxy:
  azure:
    storageAccountName: "mystorageaccount"
    storageAccountKey: "key..."
    endpoint: "https://mystorageaccount.blob.core.usgovcloudapi.net"
```

When `endpoint` is not set, it defaults to `https://<storageAccountName>.blob.core.windows.net`.

### ClickHouse Analytics Database (Optional)

The chart can deploy an internal [ClickHouse](https://clickhouse.com/) instance for analytics. ClickHouse is disabled by default and supports three modes:

1. **Internal ClickHouse** - Deploys ClickHouse within the cluster with local storage (PVC, hostPath, or RAM-backed tmpfs)
2. **External ClickHouse** - Uses an existing external ClickHouse instance
3. **Disabled** (default) - No ClickHouse

When enabled, the ClickHouse connection URL is injected into the Control Plane via `ADAPTIVE_CLICKHOUSE__URL`.

#### Option 1: Internal ClickHouse

Deploy a ClickHouse instance within your cluster. Data is stored on a PersistentVolumeClaim by default.

```yaml
clickhouse:
  enabled: true
  install:
    enabled: true  # Deploy ClickHouse in-cluster

  image:
    repository: clickhouse/clickhouse-server
    tag: "24.12-alpine"

  httpPort: 8123
  nativePort: 9000

  auth:
    username: default
    password: "your-clickhouse-password"

  database: adaptive

  # Storage for ClickHouse data
  persistence:
    enabled: true
    type: pvc  # "pvc", "hostPath", or "memory"
    # PVC options
    storageClass: ""
    size: 10Gi
    accessModes:
      - ReadWriteOnce
    # hostPath option (used when type=hostPath)
    hostPath: /var/lib/clickhouse
```

To use a hostPath volume instead of a PVC:

```yaml
clickhouse:
  persistence:
    enabled: true
    type: hostPath
    hostPath: /data/clickhouse
```

To use a RAM-backed tmpfs volume (data is lost on pod restart):

```yaml
clickhouse:
  persistence:
    enabled: true
    type: memory
    memorySizeLimit: 4Gi  # size limit for the tmpfs mount
```

#### Option 2: External ClickHouse

To use an existing external ClickHouse instance:

```yaml
clickhouse:
  enabled: true
  install:
    enabled: false  # Do not deploy ClickHouse

  external:
    url: "http://clickhouse.example.com:8123"

  auth:
    username: "clickhouse-user"
    password: "clickhouse-password"
  database: my_analytics_db
```

#### Option 3: Disable ClickHouse (Default)

```yaml
clickhouse:
  enabled: false
```

#### Configuration Options

**Mutual Exclusivity:**

- `clickhouse.install.enabled=true` and `clickhouse.external.url` cannot both be set
- `clickhouse.install.enabled=false` requires `clickhouse.external.url`
- `existingClickHouseSecret` cannot be used with inline `clickhouse.auth.password`

**Customization:**

```yaml
clickhouse:
  enabled: true
  install:
    enabled: true

  resources:
    limits:
      cpu: 4000m
      memory: 8Gi
    requests:
      cpu: 1000m
      memory: 4Gi

  podAnnotations: {}
  podLabels: {}
  nodeSelector: {}
  tolerations: []
  extraEnvVars: {}
```

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

**3. Create ExternalSecret resources** for Control Plane, Harmony, S3 credentials, Redis, and optionally ClickHouse:

> **Note:** Secret keys match the values.yaml field names for simplicity (e.g., `dbUsername`, `dbPassword`, `cookiesSecret`). The chart handles environment variable mapping internally.

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
    - secretKey: dbUsername
      remoteRef:
        key: adaptive/db-username
    - secretKey: dbPassword
      remoteRef:
        key: adaptive/db-password
    - secretKey: dbHost
      remoteRef:
        key: adaptive/db-host
    - secretKey: dbName
      remoteRef:
        key: adaptive/db-name
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
  name: adaptive-s3-creds-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: adaptive-s3-creds-secret
    creationPolicy: Owner
  data:
    - secretKey: AWS_ACCESS_KEY_ID
      remoteRef:
        key: adaptive/aws-access-key-id
    - secretKey: AWS_SECRET_ACCESS_KEY
      remoteRef:
        key: adaptive/aws-secret-access-key
    - secretKey: AWS_DEFAULT_REGION
      remoteRef:
        key: adaptive/aws-region
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
---
# ClickHouse secret (only needed when clickhouse.enabled=true)
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: adaptive-clickhouse-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: adaptive-clickhouse-secret
    creationPolicy: Owner
  data:
    - secretKey: clickhouseUrl
      remoteRef:
        key: adaptive/clickhouse-url
    - secretKey: clickhouseUsername
      remoteRef:
        key: adaptive/clickhouse-username
    - secretKey: clickhousePassword
      remoteRef:
        key: adaptive/clickhouse-password
    - secretKey: clickhouseDatabase
      remoteRef:
        key: adaptive/clickhouse-database
```

**4. Reference the secrets** in your Helm values:

```yaml
secrets:
  existingControlPlaneSecret: "adaptive-control-plane-secret"
  existingHarmonySecret: "adaptive-harmony-secret"
  existingS3CredsSecret: "adaptive-s3-creds-secret"
  existingRedisSecret: "adaptive-redis-secret"
  existingClickHouseSecret: "adaptive-clickhouse-secret"  # Only when clickhouse.enabled=true

  # Do not set inline values when using external secrets
  # db, cookiesSecret, modelRegistryUrl, sharedDirectoryUrl, s3Creds, and auth should not be set
```

**5. Deploy the Helm chart:**

```bash
helm install adaptive oci://ghcr.io/adaptive-ml/adaptive -f values.yaml
```

#### Example: Using Sealed Secrets

If you're using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets):

**1. Create your secrets** and seal them:

> **Note:** Secret keys match the values.yaml field names (e.g., `dbUsername`, `dbPassword`, `cookiesSecret`) for simplicity.

```bash
# Create control plane secret
# Note: oidcProviders must be in TOML array format
kubectl create secret generic adaptive-control-plane-secret \
  --from-literal=dbUsername="username" \
  --from-literal=dbPassword="password" \
  --from-literal=dbHost="db_address:5432" \
  --from-literal=dbName="db_name" \
  --from-literal=cookiesSecret="..." \
  --from-literal=oidcProviders='[{key=google,name=Google,issuer_url="https://accounts.google.com",client_id="...",client_secret="...",scopes=["email","profile"],pkce=true,allow_sign_up=true},]' \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-control-plane-secret.yaml

# Create harmony secret
kubectl create secret generic adaptive-harmony-secret \
  --from-literal=modelRegistryUrl="s3://..." \
  --from-literal=sharedDirectoryUrl="s3://..." \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-harmony-secret.yaml

# Create S3 credentials secret
kubectl create secret generic adaptive-s3-creds-secret \
  --from-literal=AWS_ACCESS_KEY_ID="AKxxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --from-literal=AWS_DEFAULT_REGION="us-west-2" \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-s3-creds-secret.yaml

# Create redis secret
kubectl create secret generic adaptive-redis-secret \
  --from-literal=redisUrl="redis://..." \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-redis-secret.yaml

# Create clickhouse secret (only when clickhouse.enabled=true)
kubectl create secret generic adaptive-clickhouse-secret \
  --from-literal=clickhouseUrl="http://clickhouse:8123" \
  --from-literal=clickhouseUsername="default" \
  --from-literal=clickhousePassword="password" \
  --from-literal=clickhouseDatabase="adaptive" \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-clickhouse-secret.yaml

# Apply the sealed secrets
kubectl apply -f sealed-control-plane-secret.yaml
kubectl apply -f sealed-harmony-secret.yaml
kubectl apply -f sealed-s3-creds-secret.yaml
kubectl apply -f sealed-redis-secret.yaml
kubectl apply -f sealed-clickhouse-secret.yaml  # Only when clickhouse.enabled=true
```

**2. Reference the secrets** in your Helm values as shown above.

#### Example: Manual Secret Creation

You can also create secrets manually:

> **Note:** Secret keys match the values.yaml field names (e.g., `dbUsername`, `dbPassword`, `cookiesSecret`) for simplicity.

```bash
# Control plane secret
# Note: oidcProviders must be in TOML array format
kubectl create secret generic adaptive-control-plane-secret \
  --from-literal=dbUsername="username" \
  --from-literal=dbPassword="password" \
  --from-literal=dbHost="host:5432" \
  --from-literal=dbName="db_name" \
  --from-literal=cookiesSecret="your-64-char-secret" \
  --from-literal=oidcProviders='[{key="google",name="Google",issuer_url="https://accounts.google.com",client_id="your_client_id",client_secret="your_client_secret",scopes=["email","profile"],pkce=true,allow_sign_up=true}]'

# Harmony secret
kubectl create secret generic adaptive-harmony-secret \
  --from-literal=modelRegistryUrl="s3://bucket/models" \
  --from-literal=sharedDirectoryUrl="s3://bucket/shared"

# S3 credentials secret
kubectl create secret generic adaptive-s3-creds-secret \
  --from-literal=AWS_ACCESS_KEY_ID="AKxxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --from-literal=AWS_DEFAULT_REGION="us-west-2"

# Redis secret
kubectl create secret generic adaptive-redis-secret \
  --from-literal=redisUrl="redis://redis-host:6379"

# ClickHouse secret (only when clickhouse.enabled=true)
kubectl create secret generic adaptive-clickhouse-secret \
  --from-literal=clickhouseUrl="http://clickhouse:8123" \
  --from-literal=clickhouseUsername="default" \
  --from-literal=clickhousePassword="password" \
  --from-literal=clickhouseDatabase="adaptive"
```

Then reference these secrets in your values file as shown above

---

## Monitoring and Observability

### LGTM Stack (Grafana, Loki, Tempo, Mimir, Pyroscope)

The chart includes an optional all-in-one LGTM observability stack using [`ghcr.io/grafana/docker-otel-lgtm`](https://github.com/grafana/docker-otel-lgtm). This deploys Grafana, Loki, Tempo, Mimir, Pyroscope, and an OTel Collector in a single pod.

> **Warning:** The LGTM stack is intended for **development and testing** only. For production, use dedicated observability infrastructure and configure the OTel Collector exporters to send data to your backends.

#### Enabling LGTM

```yaml
lgtm:
  enabled: true
```

When both `lgtm.enabled` and `otelCollector.enabled` are true, the chart automatically:

- Adds an `otlphttp/lgtm` exporter to the OTel Collector pointing to the LGTM pod
- Creates additional `traces/lgtm`, `metrics/lgtm`, and `logs/lgtm` pipelines that fan out telemetry to the LGTM backend (without modifying your existing pipelines)
- Sets `ADAPTIVE_GRAFANA__URL` and `ADAPTIVE_GRAFANA__LOKI_URL` environment variables on the Control Plane pod

#### Configuration

```yaml
lgtm:
  enabled: false  # Set to true to deploy

  image:
    repository: ghcr.io/grafana/docker-otel-lgtm
    tag: "v0.17.1"
    pullPolicy: IfNotPresent

  resources: {}

  persistence:
    enabled: false    # Set to true to persist data across restarts
    size: 10Gi
    storageClass: ""  # Use default storage class if empty

  # Grafana environment variables
  env:
    GF_AUTH_ANONYMOUS_ENABLED: true
    GF_AUTH_ANONYMOUS_ORG_ROLE: Admin
    GF_AUTH_DISABLE_LOGIN_FORM: true

  nodeSelector: {}
  tolerations: []
```

#### Accessing Grafana

When LGTM is enabled, Grafana is available on port 3000 of the LGTM service. You can port-forward to access it locally:

```bash
kubectl port-forward svc/<release>-adaptive-lgtm-svc 3000:3000
```

### OpenTelemetry Collector

The chart includes an [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) for collecting and exporting telemetry data (traces, metrics, and logs) from Adaptive Engine components.

For complete configuration options and advanced usage, refer to the [official OpenTelemetry Collector documentation](https://opentelemetry.io/docs/collector/configuration/).

By default, the OpenTelemetry Collector is **enabled**.

#### Configuration

```yaml
otelCollector:
  enabled: true  # Set to false to disable

  image:
    repository: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib
    tag: "0.143.1"

  replicaCount: 2  # Default replicas for high availability

  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi

  # Pod Disruption Budget (enabled by default)
  pdb:
    enabled: true
    minAvailable: 1
```

#### Fixed Receivers and Processors

The collector configuration includes fixed receivers and processors that cannot be changed:

- **Receivers**:
  - OTLP HTTP on port `4318`
  - Prometheus scraper for pods with annotation `prometheus.io/scrape: "adaptive"`
- **Processors**: `batch`, `memory_limiter`, and `resource` (for adding resource attributes)

You can adjust the memory limiter and Prometheus scraping settings:

```yaml
otelCollector:
  memoryLimitMiB: 400    # Memory limit for the processor
  memorySpikeLimit: 100  # Spike limit for the processor

  prometheus:
    scrapeInterval: "15s"  # How often to scrape metrics
```

#### Prometheus Metrics Scraping

The collector automatically scrapes Prometheus metrics from pods in the same namespace that have the following annotations:

```yaml
annotations:
  prometheus.io/scrape: "adaptive"  # Required - enables scraping
  prometheus.io/path: "/metrics"    # Optional - metrics endpoint path (default: /metrics)
  prometheus.io/port: "9090"        # Optional - metrics port
```

Adaptive Engine components (Control Plane, Harmony) are already configured with these annotations and will be automatically scraped.

#### Configuring Exporters

Configure where telemetry data is sent by customizing the `exporters` section:

```yaml
otelCollector:
  exporters: |
    # Debug exporter (logs to stdout)
    debug:
      verbosity: detailed

    # OTLP exporter to send data to another collector or backend
    otlp:
      endpoint: "your-otlp-endpoint:4317"
      tls:
        insecure: true

    # Example: Send to Jaeger
    otlp/jaeger:
      endpoint: "jaeger-collector:4317"
      tls:
        insecure: true
```

#### Configuring Pipelines

Define how data flows through the collector by customizing the `pipelines` section:

```yaml
otelCollector:
  pipelines: |
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlp]  # Use your configured exporter
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, resource, batch]
      exporters: [otlp]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlp]
```

> **Available processors:** `memory_limiter`, `resource`, `batch`
> **Available receivers:** `otlp`, `prometheus`

#### Environment Variables

When the OpenTelemetry Collector is enabled, the following environment variable is automatically added to Adaptive Engine pods (Control Plane, Sandkasten, and Harmony):

| Variable | Description |
|----------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | URL of the collector service (`http://<release>-adaptive-otel-collector-svc:4318`) |

> **Note:** Resource attributes (like `deployment.environment.name`) are applied at the collector level via the `resource` processor, not as environment variables on application pods.

#### Resource Attributes

Customize the resource attributes added to all telemetry data via the collector's `resource` processor:

```yaml
otelCollector:
  resourceAttributes:
    # Override the environment name (defaults to Helm release name)
    environmentName: "production"

    # Add extra attributes (key-value map)
    extra:
      service.namespace: ml
      deployment.region: us-east-1
```

These attributes are applied by the collector's `resource` processor to all telemetry data passing through the collector.

#### Disabling the Collector

To disable the OpenTelemetry Collector:

```yaml
otelCollector:
  enabled: false
```

When disabled, no collector is deployed and no OTEL environment variables are added to pods.

### MLflow Experiment Tracking

Adaptive Engine supports MLflow for experiment tracking and model versioning. When enabled, training jobs can log metrics, parameters, and artifacts to a dedicated MLflow tracking server.

By default, MLflow is **enabled**.

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

---

## Sandboxing service

> **Added in:** Helm chart version `0.12.0`

Sandkasten is a service for executing custom recipes in your Adaptive Engine deployment. It provides a secure environment to run user-defined workflows and custom processing tasks that integrate with the Harmony compute backend.

By default, Sandkasten is deployed with the chart. You can customize its configuration:

```yaml
sandkasten:
  replicaCount: 1
  servicePort: 3005

  image:
    repository: adaptive-repository
    tag: latest
    pullPolicy: Always

  # Optional: Add custom environment variables
  extraEnvVars:
    CUSTOM_VAR: "value"

  # Optional: Node selector for placement
  nodeSelector:
    node-type: compute

  # Optional: Tolerations for tainted nodes
  tolerations: []
```

**Note:** Sandkasten requires access to the Harmony service and artifacts storage, it uses the same service account as other Adaptive components for authentication.

---

## Compute Pools

You can define Harmony deployment groups dedicated to different workloads:

```yaml
harmony:
  computePools:
     - name: "Pool-A"
       replicas: 1
       gpusPerReplica: 8
     - name: "Pool-B"
       replicas: 2
       gpusPerReplica: 8
       nodeSelector:
         gpu-type: h100
```

Each compute pool can have its own configuration. Any values not specified will be inherited from the main `harmony` section.

### Per-Pool Node Selectors

You can specify multiple node selector labels per compute pool to target specific node types:

```yaml
harmony:
  computePools:
    - name: "inference"
      replicas: 2
      nodeSelector:
        eks.amazonaws.com/nodegroup: inference-nodes
        node.kubernetes.io/instance-type: g5.12xlarge
        topology.kubernetes.io/zone: us-east-1a
    - name: "training"
      replicas: 1
      nodeSelector:
        cloud.google.com/gke-accelerator: nvidia-tesla-a100
        cloud.google.com/gke-spot: "true"
```

---

## Storage and Persistence

### LGTM Stack

By default, LGTM data (Grafana dashboards, Loki logs, Tempo traces) is not persisted. Enable persistence to retain data across pod restarts:

```yaml
lgtm:
  persistence:
    enabled: true
    size: 10Gi
    storageClass: "your-storage-class-name"
```

---

## Extra Objects

You can create arbitrary Kubernetes resources by adding them to the `extraObjects` list. Each item is passed through `tpl`, so Helm template expressions are supported. Items can be YAML objects or multiline strings (useful for templating field names).

```yaml
extraObjects:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: my-extra-config
    data:
      key: value
  - |
      apiVersion: v1
      kind: Secret
      type: Opaque
      metadata:
        name: my-extra-secret
      data:
        password: {{ "secret" | b64enc | quote }}
```

---

## Cloud specific information

We have cloud specific information in their own docs

* [Azure](./docs/azure.md)
