# Static NFS Storage

## Purpose

Defines static NFS PersistentVolumes for pre-existing UNAS shares that need to be consumed by specific workloads (as opposed to dynamically provisioned volumes from the CSI NFS driver).

## How it works

Each subdirectory contains a `PersistentVolume` manifest backed by the UNAS NFS server (`192.168.10.5`). All volumes use the `nfs` StorageClass with `hard` mount options.

| Volume | NFS Path | Capacity | Access Mode |
|---|---|---|---|
| `unas-docs-ro` | `/var/nfs/shared/Documents` | 1Ti | ReadOnlyMany |
| `unas-k8s-rw` | `/var/nfs/shared/k8s` | 100Gi | ReadWriteMany |
| `unas-scans-rw` | `/var/nfs/shared/scans` | 1Ti | ReadWriteOnce |

## Dependencies

- The UNAS NFS server (`192.168.10.5`) must be reachable and exporting the listed paths.
- No other platform components required.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `platform`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pv unas-docs-ro unas-k8s-rw unas-scans-rw
  ```
- **Troubleshoot:** If a PV is stuck in `Released` state, check whether the bound PVC was deleted. PVs with `Retain` policy require manual cleanup.
- **Common task -- add a new static NFS volume:** Create a new subdirectory with a `pv.yaml` and `kustomization.yaml`, then add the subdirectory to the root `kustomization.yaml`.

## Secrets

None.
