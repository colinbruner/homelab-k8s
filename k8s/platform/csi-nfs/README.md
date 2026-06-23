# CSI NFS

## Purpose

Provides dynamic NFS PVC provisioning for the cluster. Workloads that need persistent storage backed by the UNAS NFS server create PVCs against the StorageClasses defined here, and the CSI driver provisions subdirectories automatically.

## How it works

The `csi-driver-nfs` Helm chart (v4.11.0) deploys the NFS CSI driver (controller + node DaemonSet) into the `csi-nfs` namespace. Two StorageClasses are created:

- **`nfs-csi`** -- dynamic provisioning under `/var/nfs/shared/k8s` on UNAS (`192.168.10.5`). Subdirectory pattern: `namespaces/<namespace>/<pvc-name>`.
- **`nfs-csi-buckets`** -- dynamic provisioning under `/var/nfs/shared/buckets`. Subdirectory pattern: `<namespace>/<pvc-name>`.

Both use NFSv3 with `nolock` (UNAS does not support NFSv4). Reclaim policy is `Retain`.

## Dependencies

- The UNAS NFS server (`192.168.10.5`) must be reachable and exporting the expected paths.
- No other platform components required.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `platform`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n csi-nfs
  kubectl get storageclasses nfs-csi nfs-csi-buckets
  kubectl get pvc -A --field-selector=spec.storageClassName=nfs-csi
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n csi-nfs -l app=csi-nfs-controller --tail=50
  kubectl describe pvc <name> -n <namespace>
  ```

## Secrets

None.
