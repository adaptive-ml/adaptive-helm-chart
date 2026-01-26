<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Upgrade Guide](#upgrade-guide)
  - [0.29.x to 0.30.0](#029x-to-0300)
    - [Breaking Change: Service Account Split](#breaking-change-service-account-split)
  - [0.24.x to 0.25.0](#024x-to-0250)
    - [Breaking Change: Harmony Compute Pools Configuration](#breaking-change-harmony-compute-pools-configuration)
  - [0.17.x to 0.18.0](#017x-to-0180)
    - [Breaking Change: Database Configuration Format](#breaking-change-database-configuration-format)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Upgrade Guide

This document describes breaking changes between Helm chart versions and how to migrate your configuration.

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
      # capabilities: "TRAINING,INFERENCE,EVALUATION"
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
      capabilities: "TRAINING,EVALUATION"

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
