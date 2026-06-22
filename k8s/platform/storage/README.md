# platform/storage

Static NFS PersistentVolumes for UNAS shares.

## Volumes

- **unas-docs-ro** -- Read-only documents (`/var/nfs/shared/Documents`, 1Ti)
- **unas-k8s-rw** -- K8s cluster data (`/var/nfs/shared/k8s`, 100Gi, ReadWriteMany)
- **unas-scans-rw** -- Scanned documents (`/var/nfs/shared/scans`, 1Ti, ReadWriteOnce)

All volumes use the `nfs` StorageClass with `hard` mount options against NFS server `192.168.10.5`.
