# Helm Chart for Adaptive Engine

A Helm Chart to deploy Adaptive Engine.

## Installing the Chart

[Helm](https://helm.sh) must be installed to use the charts.

---

## Prerequisites

1. Nvidia operator installed in the target k8s cluster: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html>
2. k8s version >=1.26.

3. For inference autoscaling. Adaptive engine supports horizontal pods scaling for inference fleets. This is automatic based on Qos metrics (TTFT), and technical metrics (required gpus vs available gpus). For the target k8s cluster to support nodes austocaling. Those requirements should be met:
    - *Cluster Autoscaler* enabled and correctly configured.
    - Node pool (or equivalent in your cloud provider) should allow scaling GPU nodes.
    - Your cloud provider must support on-demand provisioning of GPU instances.

4. Storage classes: for logs and Prometheus timeseries persistence. for further details see section `About persistence and volumes`

##### 1. Add the charts from this repository:

```
helm repo remove adaptive 2>/dev/null
helm repo add adaptive https://adaptive-ml.github.io/adaptive-helm-chart/
helm repo update adaptive
```

You can then run `helm search repo adaptive` to see the charts.
There are 2 charts in this repo: 
- `adaptive`, the main chart to deploy Adaptive Engine
- `monitoring`, an optional addon chart to monitor Adaptive Engine logs with Grafana

##### 2. Get the default values.yaml configuration file: 

```
helm show values adaptive/adaptive > values.yaml
helm show values adaptive/monitoring > values.monitoring.yaml
```

##### 3. Edit the values.yaml file to customize the Helm chart for your environment. Here are the key sections:

###### Secrets for model registry, database and auth
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
###### Container images
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

###### GPU Resources
```yaml
harmony:
    # Should be equal to, or a divisor of the # of GPUs on each node
    gpusPerReplica: 8
```

See the full `charts/adaptive/values.yaml` file for further customization.

##### 4. Deploy the chart with

```
helm install adaptive adaptive/adaptive -f ./values.yaml
helm install adaptive-monitoring adaptive/monitoring -f ./values.monitoring.yaml
```

If you deploy the addon adaptive-monitoring chart, make sure to override the default value of `grafana.proxy.domain` in the `values.monitoring.yaml` file retrieved in step #2; it must match the value of your igress domain (`controlPlane.rootUrl`) for Adaptive Engine
(as a fully qualified domain name, no scheme). Once deployed, you will be able to access the Grafana dashboard for logs monitoring at your ingress domain + `/monitoring/explore`.

## Using external secrets

This repository includes an example integration with [External Secrets Operator](https://external-secrets.io/latest/).

If you are storing secrets in an external/cloud secrets manager, you can use them in your Adaptive Engine deployment by following these steps:

1. Install External Secrets Operator (reference installation guide [here](https://external-secrets.io/latest/introduction/getting-started/))

```
helm repo add external-secrets https://charts.external-secrets.io

helm install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace
```

2. Customize the example values file `charts/adaptive/values_external_secret.yaml` to match your secrets provider and external secret configuration.

3. Deploy the Helm chart using the updated values file

```
helm install adaptive adaptive/adaptive -f charts/adaptive/values_external_secret.yaml
```

## About persistence and volumes

- **monitoring** stack helm chart: by default Logs and Grafana data are not persisted. You should enable `grafana.enablePersistence=true` and set `grafana.storageClass` to an existing storage class name in target k8s cluster.
- **adaptive** helm chart: it installs Prometheus which may require metrics data being persisted. By default `prometheus.server.persistentVolume.enabled=false`. When enabling peristence, i'll have to specify the used storage class name: `prometheus.server.storageClass`.