# Garage

## Purpose

S3-compatible distributed object storage for the homelab. Provides an S3 API, a static website serving endpoint, and an admin API.

## How it works

A single-replica Deployment runs `dxflrs/garage:v1.0.1` with `replication_mode = "none"` (single-node). Configuration is supplied via a `ConfigMap` (`garage-config`) containing `garage.toml`. Data is stored on a 1Ti PVC backed by the `nfs-csi-buckets` StorageClass.

Exposed ports and their HTTPRoutes:

| Port | Service | Hostname |
|---|---|---|
| 3900 | S3 API | (cluster-internal only) |
| 3901 | RPC | (cluster-internal only) |
| 3902 | S3 Web | `garage.colinbruner.com` / `garage-internal.colinbruner.com` |
| 3903 | Admin API | `garage-admin.colinbruner.com` / `garage-admin-internal.colinbruner.com` |

The RPC secret is injected from the `garage-secret` Kubernetes Secret (key: `rpc_secret`).

## Dependencies

- **1password** -- operator must be running to provision the `garage-secret`.
- **csi-nfs** -- the `nfs-csi-buckets` StorageClass must exist for the data PVC.
- **gateway** -- the shared Gateway and `garage-tls` certificate must exist for the HTTPRoutes.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `apps`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n garage
  kubectl get pvc -n garage
  kubectl get httproutes -n garage
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n garage deploy/garage --tail=50
  kubectl exec -n garage deploy/garage -- /garage status
  ```
- **Common task -- manage buckets:**
  ```bash
  kubectl exec -n garage deploy/garage -- /garage bucket list
  kubectl exec -n garage deploy/garage -- /garage bucket create <bucket-name>
  kubectl exec -n garage deploy/garage -- /garage key list
  ```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `garage-secret` | `rpc_secret` | OnePasswordItem (`vaults/lab/items/garage-s3`) -- 64-character lowercase hex string |
