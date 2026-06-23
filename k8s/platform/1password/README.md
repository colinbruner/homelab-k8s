# 1Password Connect + Operator

## Purpose

Deploys the 1Password Connect server and Kubernetes operator. The operator watches for `OnePasswordItem` custom resources and pulls secrets from the `homelab` vault into native Kubernetes `Secret` objects. This is the cluster's root-of-trust for secret injection -- every other component that needs a secret uses a `OnePasswordItem` CR rather than storing credentials in git.

## How it works

The `1password/connect` Helm chart (v2.4.1) deploys the Connect server and operator into the `1password` namespace. The chart references two pre-existing secrets (`op-credentials` and `op-connect-token`) that authenticate the operator against 1Password. Once running, any namespace can create a `OnePasswordItem` CR and the operator will materialize a matching Kubernetes `Secret`.

## Dependencies

None -- this is the first component deployed. The two root-of-trust secrets must already exist in the namespace, created by `bootstrap/bootstrap.sh` before ArgoCD syncs this component.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `platform`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n 1password
  kubectl get onepassworditems -A
  ```
- **Troubleshoot:** If secrets are not being created, check the operator logs:
  ```bash
  kubectl logs -n 1password -l app=onepassword-connect-operator --tail=50
  ```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `op-credentials` | `1password-credentials.json` | Manual -- 1Password vault document export, created by `bootstrap.sh` |
| `op-connect-token` | `token` | Manual -- 1Password Connect access token, created by `bootstrap.sh` |

These are the manual root-of-trust secrets. They are **not** stored in git.
