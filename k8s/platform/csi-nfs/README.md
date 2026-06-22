# platform/csi-nfs

CSI NFS driver and StorageClasses for dynamic NFS PVC provisioning against UNAS shares.

## Components

- **csi-driver-nfs** Helm chart (v4.11.0) -- deploys the NFS CSI driver into the `csi-nfs` namespace.
- **nfs-csi** StorageClass -- dynamic provisioning under `/var/nfs/shared/k8s` (configured via `values.yaml`).
- **nfs-csi-buckets** StorageClass -- dynamic provisioning under `/var/nfs/shared/buckets`.

Both StorageClasses use NFSv3 with `nolock` (UNAS does not support NFSv4).
