# backup-documents

## Purpose

Backs up the UNAS Documents NFS share to Google Cloud Storage (GCS) on a daily schedule using Kopia. Chronos health-check pings confirm each backup completed successfully.

## How it works

Uses the local `packages/helm/kopia` chart (appVersion 0.23.1) deployed via Kustomize helmCharts. The chart creates:

- A static NFS PV/PVC mounting `/var/nfs/shared/Documents` read-only into the pod at `/Volumes/Documents`.
- A dynamic NFS PVC (`config`, via `nfs-csi`) for Kopia cache and repository metadata.
- An init container that creates or connects to the GCS repository and sets the snapshot policy.
- A long-running Kopia server container (port 8080) with `--enable-actions` for Chronos hooks.
- A `OnePasswordItem` for the repository password (`backup`) and Chronos token (`chronos`).

Backup schedule: `15 4 * * *` (daily at 4:15 AM CT). GCS bucket: `backup-unas-vol-documents-9851`.

## Dependencies

- **1password** -- operator must be running to provision `backup` and `chronos` secrets.
- **csi-nfs** -- the `nfs-csi` StorageClass must exist for the config PVC.
- **storage** -- the UNAS NFS server (`192.168.10.5`) must be reachable.
- The `gcp-credentials` secret must be manually created before first deployment.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `apps`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n backup-documents
  kubectl logs -n backup-documents -l app.kubernetes.io/name=kopia --tail=20
  ```
- **Access the Kopia UI:**
  ```bash
  kubectl port-forward -n backup-documents svc/backup 8080:8080
  # Open http://localhost:8080
  ```
- **Trigger a manual snapshot:**
  ```bash
  kubectl exec -n backup-documents deploy/backup -- kopia snapshot create /Volumes/Documents
  ```

### Backup/Restore playbook

**Check repository status:**
```bash
kubectl exec -n backup-documents deploy/backup -- kopia repository status
kubectl exec -n backup-documents deploy/backup -- kopia snapshot list
```

**Restore from GCS (from any machine with Kopia installed):**

1. Obtain the GCP service account JSON and repository password.
2. Connect to the repository:
   ```bash
   export KOPIA_PASSWORD='<repository-password>'
   kopia repository connect gcs \
     --bucket backup-unas-vol-documents-9851 \
     --credentials-file /path/to/sa.json
   ```
3. List available snapshots:
   ```bash
   kopia snapshot list
   ```
4. Restore a snapshot:
   ```bash
   kopia restore <snapshot-id> /path/to/restore/target
   ```

**Restore via port-forward (in-cluster):**
```bash
kubectl port-forward -n backup-documents svc/backup 8080:8080
# Use the Kopia web UI at http://localhost:8080 to browse and restore snapshots.
```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `gcp-credentials` | `sa_json` | **Manual** -- GCP service account JSON for GCS access. Must be created in the `backup-documents` namespace before the backup can run. Not stored in git. |
| `backup` | `password` | OnePasswordItem (`vaults/lab/items/UNAS Backup Password`) |
| `chronos` | `token` | OnePasswordItem (`vaults/lab/items/Chronos Backup Documents`) |
