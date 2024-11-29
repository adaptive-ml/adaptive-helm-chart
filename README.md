# Helm Chart for Adaptive Engine
A Helm Chart to deploy Adaptive Engine

## Installing the Chart
-----------------------
1. Add the chart from this repository:

```
$ helm repo add adaptive https://raw.githubusercontent.com/adaptive-ml/adaptive-helm-chart/main/charts
$ helm repo update adaptive
```

2. Customize the `[[auth.oidc.providers]]` section in the `adaptive_configs/config.toml` file to setup authentication for the Adaptive UI.

3. Install the chart on a Kubernetes cluster by running the following, replacing the minimal required values:
```
$ helm install adaptive adaptive/adaptive \
    --set secrets.modelRegistryUrl="s3://your-bucket/dir" \
    --set secrets.dbUrl="postgres://username:password@db_adress:5432/db_name" \
    --set harmony.gpusPerNode=8 \
    --set containerRegistry="adaptive-container-registry" \
    --set harmony.image.repository="harmony-container-repository" \
    --set harmony.image.tag="harmony-container-tag" \
    --set controlPlane.image.repository="control-plane-container-repository" \
    --set controlPlane.image.tag="control-plane-container-tag" \

    
```
You can also update the values in `charts/adaptive/values.yaml` instead for more customizations, and deploy the chart with:
```
$ helm install adaptive adaptive/adaptive -f ./charts/adaptive/values.yaml
```

## Using external secrets
This repository includes an example integration with [External Secrets Operator](https://external-secrets.io/latest/).

If you are storing secrets in an external/cloud secrets manager, you can directly use them in your Adaptive Engine deployment by following these steps:

1. Install External Secrets Operator (reference installation guide [here](https://external-secrets.io/latest/introduction/getting-started/))
```
$ helm repo add external-secrets https://charts.external-secrets.io

$ helm install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace
```

2. Customize the example values file `charts/adaptive/values_external_secret.yaml` to match your secrets provider and external secret configuration.


3. Deploy the Helm chart using the updated values file
```
$ helm install adaptive adaptive/adaptive -f charts/adaptive/values_external_secret.yaml
```

 





