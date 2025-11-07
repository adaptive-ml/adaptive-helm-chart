<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Azure Specific Information](#azure-specific-information)
  - [Storage](#storage)
  - [Compute](#compute)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Azure Specific Information

<!-- toc -->

- [Compute](#compute)

<!-- tocstop -->

## Storage

The recommendation for Azure is to use PVC backed by [Azure Files](https://azure.microsoft.com/en-us/products/storage/files) in order to store the model registry and working directory.

This is done for the following reasons:
* Native integration with Azure. The lifecycle of Azure Files are fully managed on Azure side without having to pass credentials.
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
      storage: 500Gi
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
      claimName: adaptive-workdir-premium
```

> [!NOTE]
> There is still a deprecated S3Proxy available in the helm chart. S3proxy integration is not optimal for recent versions of Adaptive and we recommend instead using the simpler route of k8s PVC.


## Compute

Adaptive recommendation is to use at least 2 different compute pools
- A GPU nodepool that will host the `harmony` pods.
- A CPU nodepool that will host the other non-gpu pods (control-plane, redis, ...)

This is done in order to guarantee that the compute plane has access to all the gpus resources and that the control plane is scheduled on cheaper nodes.
