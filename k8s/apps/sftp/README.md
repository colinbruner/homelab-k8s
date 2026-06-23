# SFTP

## Purpose

Provides an SFTP server for receiving scanned documents from a network scanner. Files uploaded via SFTP are written directly to the UNAS scans NFS share.

## How it works

A single-replica Deployment runs the custom `despitehowever/sftp:latest` image (built from `build/sftp/`). The container mounts the `unas-scans-rw` static NFS PV at `/home/scanner/in` and the SSH host key from a 1Password-managed secret at `/var/sftp-key`.

The Service is type `LoadBalancer` (port 22), so MetalLB assigns it a dedicated IP. The scanner connects directly to this IP over the LAN.

## Dependencies

- **1password** -- operator must be running to provision the `sftp-hostkey` secret.
- **storage** -- the `unas-scans-rw` PV must exist (defined in `k8s/platform/storage/`).
- **metallb** -- assigns the LoadBalancer IP.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `apps`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n sftp
  kubectl get svc -n sftp
  kubectl get pvc -n sftp
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n sftp deploy/sftp --tail=50
  # Test SFTP connectivity
  sftp scanner@<loadbalancer-ip>
  ```
- **Find the LoadBalancer IP:**
  ```bash
  kubectl get svc sftp -n sftp -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  ```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `sftp-hostkey` | (SSH host key) | OnePasswordItem (`vaults/lab/items/SFTP - Server`) |
