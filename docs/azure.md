# Azure Specific Information

This page lists information for a deployment on Azure platform with [AKS](https://learn.microsoft.com/en-us/azure/aks/) as a kubernetes cluster

## Table of contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Compute](#compute)
  - [Requirements for nodepools](#requirements-for-nodepools)
- [Storage](#storage)
- [Networking](#networking)
  - [CNI](#cni)
  - [Ingress](#ingress)
- [Authentication](#authentication)
  - [Process](#process)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


## Compute

Adaptive recommends to use at least 2 different compute pools
* A GPU nodepool that will host the `harmony` pods.
* A CPU nodepool that will host the other non-gpu pods (control-plane, redis, ...)

This is done in order to guarantee that the compute plane has access to all the gpus resources and that the control plane is scheduled on cheaper nodes.

### Requirements for nodepools

* Nodepools need to have a x86_64 cpu. Adaptive does not currently support ARM architectures.
* The [maximum pods per node](https://learn.microsoft.com/en-us/azure/aks/concepts-network-ip-address-planning#maximum-pods-per-node) needs to be *at least 50*
* The CPU nodepool vms should have at least 32GB of memory and at least 8 vCPUs. Our recommended instance type is Standard_D16as_v6 with 16 vCPUs and 64GB of memory


## Storage

The recommendation for Azure is to use PVC backed by [Azure Files](https://azure.microsoft.com/en-us/products/storage/files) in order to store the model registry and working directory.

This is done for the following reasons:
* Native integration with Azure. The lifecycle of Azure Files is fully managed on Azure side without having to pass credentials.
* Easy resize. By just changing the PVC you can increase the amount of storage available.
* Shared State. Since this storage class is ReadWriteMany all of the pods of adaptive can share state

In order to do that you will need to create an adaptive specific Storage Class and the 2 PVCs that will store the data
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  labels:
    kubernetes.io/cluster-service: "true"
  name: azurefile-csi-premium-adaptive
allowVolumeExpansion: true
mountOptions:
- mfsymlinks
- actimeo=30
- nosharesock
- uid=1002
- gid=1002
parameters:
  skuName: Premium_LRS
provisioner: file.csi.azure.com
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: adaptive-model-registry
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefile-csi-premium-adaptive
  resources:
    requests:
      storage: 1500Gi
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: adaptive-workdir
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefile-csi-premium-adaptive
  resources:
    requests:
      storage: 500Gi
```

Then you will need to make sure that you have the following values for the helm chart
```yaml
secrets:
  modelRegistryUrl: /model_registry
  sharedDirectoryUrl: /workdir
controlPlane:
  sharedDirType: local
volumeMounts:
  - name: model-registry
    mountPath: /model_registry
  - name: working-directory
    mountPath: /workdir
volumes:
  - name: model-registry
    persistentVolumeClaim:
      claimName: adaptive-model-registry
  - name: working-directory
    persistentVolumeClaim:
      claimName: adaptive-workdir
```

> [!NOTE]
> There is still a deprecated S3Proxy available in the helm chart. S3proxy integration is not optimal for recent versions of Adaptive and we recommend instead using the simpler route of k8s PVC.

## Networking

### CNI

Adaptive recommends to use [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay) as a CNI for the cluster. This ensures best scalability and reliability. While other CNI may work they are not as extensively tested with Adaptive.

### Ingress

An Ingress is a way to expose services running inside a k8s cluster to the outside.

Adaptive recommends to use [Application routing add-on](https://learn.microsoft.com/en-us/azure/aks/app-routing) as an ingress controller.

You can validate that the add-on is enabled in your cluster with the following command:
```bash
$ kubectl get ingressclass webapprouting.kubernetes.azure.com
NAME                                 CONTROLLER                                 PARAMETERS   AGE
webapprouting.kubernetes.azure.com   webapprouting.kubernetes.azure.com/nginx   <none>
```

If you get the following error
```Error from server (NotFound): ingressclasses.networking.k8s.io "webapprouting.kubernetes.azure.com" not found``` it means that the add-on is not installed and you should follow [these instructions](https://learn.microsoft.com/en-us/azure/aks/app-routing#enable-application-routing-using-azure-cli) in order to install it.


Once the add-on is installed you can use these values in the helm chart in order to configure the ingress.
You need to replace `<hostname>` with your desired hostname for adaptive
```yaml
controlPlane:
    rootUrl: https://<hostname>
ingress:
  enabled: true
  className: webapprouting.kubernetes.azure.com
  hosts:
    - host: <hostname>
      paths:
        - path: /
          pathType: Prefix
```


Once you have applied the helm you can check the ingress to validate that everything is ok
```bash
$ kubectl get ingress
NAME                    CLASS                                HOSTS        ADDRESS        PORTS
adaptive-controlplane   webapprouting.kubernetes.azure.com   <hostname>   <ip_address>   80, 443
```



#### Private Ingress

The default ingress add-on creates a public load-balancer exposed directly to the Internet. If you only want to open adaptive to your [vnet](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) you can follow these steps


1. Create an `internal` ingressClass
```yaml
apiVersion: approuting.kubernetes.azure.com/v1alpha1
kind: NginxIngressController
metadata:
  name: internal
spec:
  controllerNamePrefix: nginx-internal
  ingressClassName: internal
  loadBalancerAnnotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

2. Use `internal` as an ingress class in your values.yaml
```yaml
ingress:
  className: internal
```

## Authentication

We support OIDC as authentication protocol. In an Azure environment this is provided by [Azure Entra ID](https://www.microsoft.com/en-us/security/business/identity-access/microsoft-entra-id).

### Process

1. Create a new App registration in your Tenant
2. Ensure the redirect URI is `<Adaptive Engine URL>/api/v1/auth/login/azure/callback`
3. Copy Client ID from you App registration
4. Add a new "Client Secret" and store the newly created secret
5. In your `values.yaml` you should have a block like this
```yaml
secrets:
  auth:
    oidc:
      providers:
        - name: "Azure"
          key: "azure"
          issuer_url: "https://login.microsoftonline.com/<tenant_id>/v2.0"
          client_id: "<client_id>"
          client_secret: "<client_secret>"
          scopes: ["email", "profile"]
          pkce: true
          allow_sign_up: true
          require_email_verified: false
```

> [!IMPORTANT]
> The field `require_email_verified: false` is required to ensure oidc works with Entra ID
