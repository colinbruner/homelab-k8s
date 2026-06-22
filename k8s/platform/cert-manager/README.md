# cert-manager

## Purpose

Manages TLS certificate issuance for the cluster via Let's Encrypt. All HTTPS services terminate TLS using certificates issued and automatically renewed by cert-manager.

## How it works

The cert-manager Helm chart (v1.16.2) deploys the certificate controller with CRDs enabled. Two `ClusterIssuer` resources (`letsencrypt-prod` and `letsencrypt-staging`) are configured for ACME DNS-01 challenges via the Cloudflare API. A `OnePasswordItem` named `cloudflare` injects the Cloudflare API token (from `vaults/lab/items/Cloudflare`) used by both issuers to solve DNS challenges.

## Dependencies

- **1password** -- the OnePasswordItem operator must be running to materialize the `cloudflare` secret.
- Outbound HTTPS access to the Let's Encrypt ACME directory and the Cloudflare API.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `platform`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n cert-manager
  kubectl get clusterissuers
  kubectl get certificates -A
  ```
- **Troubleshoot:** Check cert-manager controller logs and certificate status:
  ```bash
  kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=50
  kubectl describe certificate <name> -n <namespace>
  kubectl describe certificaterequest -n <namespace>
  ```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `cloudflare` | `token` | OnePasswordItem (`vaults/lab/items/Cloudflare`) |
