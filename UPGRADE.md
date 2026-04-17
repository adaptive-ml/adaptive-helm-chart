<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Upgrade Guide](#upgrade-guide)
  - [0.47.x to 0.48.0](#047x-to-0480)
    - [Breaking Change: Internal API JWT Private Key Required](#breaking-change-internal-api-jwt-private-key-required)
  - [0.41.x to 0.42.0](#041x-to-0420)
    - [Breaking Change: S3 Credentials and Secret Defaults](#breaking-change-s3-credentials-and-secret-defaults)
  - [0.37.x to 0.38.0](#037x-to-0380)
    - [Breaking Change: Monitoring Chart Merged into Adaptive Chart](#breaking-change-monitoring-chart-merged-into-adaptive-chart)
  - [0.29.x to 0.30.0](#029x-to-0300)
    - [Breaking Change: Service Account Split](#breaking-change-service-account-split)
  - [0.24.x to 0.25.0](#024x-to-0250)
    - [Breaking Change: Harmony Compute Pools Configuration](#breaking-change-harmony-compute-pools-configuration)
  - [0.17.x to 0.18.0](#017x-to-0180)
    - [Breaking Change: Database Configuration Format](#breaking-change-database-configuration-format)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Upgrade Guide

This document describes breaking changes between Helm chart versions and how to migrate your configuration.

## 0.47.x to 0.48.0

### Breaking Change: Internal API JWT Private Key Required

A new required secret value, `secrets.auth.internalJwtPrivateKeyV4Base64`, has been added to the Control Plane. It is loaded as the `ADAPTIVE_AUTH__INTERNAL_API_JWT__PRIVATE_KEY_V4_BASE64` environment variable and is used to sign internal API JWTs. The chart deployment will fail if it is not provided.

**Generating the key:**

Use the helper script shipped in this repo:

```bash
./scripts/generate-internal-jwt-key.sh
```

See [`scripts/README.md`](./scripts/README.md#generate-internal-jwt-keysh) for requirements and the equivalent raw OpenSSL commands for environments where the script cannot be run.

**Migration:**

If you are using inline secret values, add the new key under `secrets.auth`:

```yaml
secrets:
  auth:
    internalJwtPrivateKeyV4Base64: "<base64-encoded-private-key>"
```

If you are using `secrets.existingControlPlaneSecret`, add an `internalJwtPrivateKeyV4Base64` key to your pre-existing secret. The full list of required keys is now: `dbUsername`, `dbPassword`, `dbHost`, `dbName`, `cookiesSecret`, `oidcProviders`, `internalJwtPrivateKeyV4Base64`.

The value must be the same on all servers of a cluster.

## 0.41.x to 0.42.0

### Breaking Change: S3 Credentials and Secret Defaults

#### S3 credentials moved to `secrets.s3Creds`

S3/MinIO credentials are now managed through a dedicated `secrets.s3Creds` secret instead of being injected as individual environment variables. All keys in `secrets.s3Creds` are loaded as environment variables on control-plane, harmony, and sandkasten pods via `envFrom`.

When `minio.enabled` is true, the following keys are auto-populated (user values take precedence):
- `AWS_ACCESS_KEY_ID` (from `minio.auth.rootUser`)
- `AWS_SECRET_ACCESS_KEY` (from `minio.auth.rootPassword`)
- `AWS_DEFAULT_REGION` (`us-east-1`)
- `AWS_ENDPOINT_URL_S3` (MinIO service endpoint)
- `S3_FORCE_PATH_STYLE` (`true`)

You can also reference a pre-existing secret via `secrets.existingS3CredsSecret`.

**If you were relying on `minio.enabled` to inject AWS credentials:** No action needed — the chart now auto-populates `s3Creds` from the MinIO config.

**If you were providing AWS credentials through a different mechanism (e.g., IRSA, pod annotations, extraEnvVars):** No action needed — `s3Creds` defaults to empty and no secret is created.

**If you want to provide S3 credentials inline:**

```yaml
secrets:
  s3Creds:
    AWS_ACCESS_KEY_ID: "AKxxx"
    AWS_SECRET_ACCESS_KEY: "xxx"
    AWS_REGION: "us-west-2"
    AWS_DEFAULT_REGION: "us-west-2"
```

#### Secret values no longer have placeholder defaults

Inline secret values (`secrets.db.*`, `secrets.cookiesSecret`, `secrets.modelRegistryUrl`, `secrets.sharedDirectoryUrl`, `secrets.auth.oidc.providers`) now default to empty strings/empty list instead of placeholder values like `s3://bucket-name/model_registry` or `username`. This prevents accidentally deploying with placeholder credentials.

**Migration:** If your values file was relying on the chart defaults (not recommended), you must now explicitly set all required secret values.

## 0.37.x to 0.38.0

### Breaking Change: Monitoring Chart Merged into Adaptive Chart

The standalone `monitoring` chart (`charts/monitoring/`) has been removed. Its functionality is now available as an optional component in the main `adaptive` chart under the `lgtm` key.

**What changed:**

- The `monitoring` chart is no longer published as a separate OCI artifact
- The LGTM observability stack (Grafana, Loki, Tempo, Mimir, Pyroscope) is now deployed via `lgtm.enabled: true` in the adaptive chart
- When both `lgtm.enabled` and `otelCollector.enabled` are true, the OTel Collector is auto-configured to send telemetry to the LGTM backend, and the Control Plane receives `ADAPTIVE_GRAFANA__URL` and `ADAPTIVE_GRAFANA__LOKI_URL` environment variables

**Migration steps:**

1. Remove the standalone monitoring release:
   ```bash
   helm uninstall adaptive-monitoring
   ```

2. Enable LGTM in your adaptive values file:
   ```yaml
   lgtm:
     enabled: true

     # Optional: carry over any custom settings from your old monitoring values
     persistence:
       enabled: true       # if you had persistence enabled
       size: 10Gi
       storageClass: ""

     env:
       GF_AUTH_ANONYMOUS_ENABLED: true
       GF_AUTH_ANONYMOUS_ORG_ROLE: Admin
       GF_AUTH_DISABLE_LOGIN_FORM: true
   ```

3. Upgrade the adaptive release:
   ```bash
   helm upgrade adaptive oci://ghcr.io/adaptive-ml/adaptive -f values.yaml
   ```

**Note:** If you had persistent data in the old monitoring chart, you will need to manually migrate it — the new LGTM deployment creates its own PVC.

## 0.29.x to 0.30.0

### Breaking Change: Service Account Split

The single global `serviceAccount` configuration has been replaced with three separate service accounts, one for each main component: control plane, harmony, and sandkasten.

**Removed fields:**
- `serviceAccount.create` - Use `controlPlane.serviceAccount.create`, `harmony.serviceAccount.create`, `sandkasten.serviceAccount.create` instead
- `serviceAccount.automount` - Removed, defaults to `true`
- `serviceAccount.annotations` - Use per-component `serviceAccount.annotations` instead
- `serviceAccount.name` - Use per-component `serviceAccount.name` instead

**Old format (0.29.x and earlier):**

```yaml
serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: serviceaccount.adaptive-ml.com
```

**New format (0.30.0+):**

```yaml
controlPlane:
  serviceAccount:
    create: true
    annotations: {}
    name: ""

harmony:
  serviceAccount:
    create: true
    annotations: {}
    name: ""

sandkasten:
  serviceAccount:
    create: true
    annotations: {}
    name: ""
```

**New service account names:**

| Component     | Service Account Name            |
|---------------|--------------------------------|
| Control Plane | `<release>-controlplane-sa`    |
| Harmony       | `<release>-harmony-sa`         |
| Sandkasten    | `<release>-sandkasten-sa`      |

**Migration steps:**

1. Remove the global `serviceAccount` section from your values file
2. Add `serviceAccount` sections under `controlPlane`, `harmony`, and `sandkasten`
3. If using IAM roles (IRSA on AWS or Workload Identity on GCP), update your IAM bindings for each new service account name

**Example: IAM role migration**

If you had:
```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/adaptive-role
  name: adaptive-sa
```

Change to:
```yaml
controlPlane:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/adaptive-controlplane-role

harmony:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/adaptive-harmony-role

sandkasten:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/adaptive-sandkasten-role
```

**Using existing service accounts:**

```yaml
controlPlane:
  serviceAccount:
    create: false
    name: my-existing-controlplane-sa

harmony:
  serviceAccount:
    create: false
    name: my-existing-harmony-sa

sandkasten:
  serviceAccount:
    create: false
    name: my-existing-sandkasten-sa
```

## 0.24.x to 0.25.0

### Breaking Change: Harmony Compute Pools Configuration

The Harmony StatefulSet configuration has been restructured to support multiple compute pools. Each compute pool creates a separate StatefulSet and headless Service, allowing you to deploy different configurations for training, inference, and evaluation workloads.

**Removed fields:**
- `harmony.replicaCount` - Use `harmony.computePools[].replicas` instead
- `harmony.group` - Use `harmony.computePools[].name` instead
- `harmony.partitionKey` - Now automatically derived from pool name

**Old format (0.24.x and earlier):**

```yaml
harmony:
  enabled: true
  group: default
  partitionKey: default-statefulset
  replicaCount: 1
  gpusPerReplica: 8
  resources:
    limits:
      cpu: 30
      memory: 500Gi
    requests:
      cpu: 30
      memory: 500Gi
  nodeSelector: {}
  tolerations:
    - key: "nvidia.com/gpu"
      operator: "Exists"
      effect: "NoSchedule"
```

**New format (0.25.0+):**

```yaml
harmony:
  enabled: true
  # Default values inherited by all compute pools (can be overridden per pool)
  resources:
    limits:
      cpu: 30
      memory: 500Gi
    requests:
      cpu: 30
      memory: 500Gi
  nodeSelector: {}
  tolerations:
    - key: "nvidia.com/gpu"
      operator: "Exists"
      effect: "NoSchedule"

  # List of compute pools - each creates a separate StatefulSet and headless Service
  computePools:
    - name: default        # Used as GROUP and to derive PARTITION_KEY
      replicas: 1          # Number of replicas for this pool
      gpusPerReplica: 8
      # Optional per-pool overrides:
      # capabilities: "JOB,INFERENCE"
      # resources: {}
      # nodeSelector: {}
      # tolerations: []
```

**Migration steps:**

1. Move `harmony.replicaCount` to `harmony.computePools[0].replicas`
2. Move `harmony.group` to `harmony.computePools[0].name`
3. Remove `harmony.partitionKey` (now auto-derived from pool name)
4. Keep default values (`gpusPerReplica`, `resources`, `tolerations`, etc.) at the `harmony` level - they will be inherited by all pools

**Example: Single pool migration**

If you had:
```yaml
harmony:
  group: my-gpu-pool
  partitionKey: my-partition
  replicaCount: 2
  gpusPerReplica: 4
```

Change to:
```yaml
harmony:
  gpusPerReplica: 4
  computePools:
    - name: my-gpu-pool
      replicas: 2
```

**Example: Multiple pools**

You can now define multiple compute pools with different configurations:

```yaml
harmony:
  gpusPerReplica: 8  # Default for all pools
  resources:
    limits:
      cpu: 30
      memory: 500Gi
    requests:
      cpu: 30
      memory: 500Gi

  computePools:
    - name: training
      replicas: 2
      capabilities: "JOB"

    - name: inference
      replicas: 4
      gpusPerReplica: 4  # Override default
      capabilities: "INFERENCE"
      resources:         # Override default
        limits:
          cpu: 16
          memory: 128Gi
        requests:
          cpu: 16
          memory: 128Gi
```

This creates:
- `<release>-harmony-training` StatefulSet with 2 replicas
- `<release>-harmony-training-hdls` headless Service
- `<release>-harmony-inference` StatefulSet with 4 replicas
- `<release>-harmony-inference-hdls` headless Service

## 0.17.x to 0.18.0

### Breaking Change: Database Configuration Format

The `secrets.dbUrl` field has been replaced with separate database configuration fields.

**Old format (0.17.x and earlier):**

```yaml
secrets:
  dbUrl: "postgresql://username:password@db_address:5432/db_name"
```

**New format (0.18.0+):**

```yaml
secrets:
  db:
    username: "username"
    password: "password"
    host: "db_address:5432"  # Host and port
    database: "db_name"
```
