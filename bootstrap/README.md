# Bootstrap

One-time cluster bootstrap script. Creates the 1Password root secrets, installs ArgoCD, and applies the GitOps root ApplicationSets. After this, ArgoCD converges everything else.

## Prerequisites

- `kubectl` configured with admin access to the target cluster
- `kustomize` and `helm` in PATH
- 1Password CLI (`op`) signed in to the `homelab` account

## Root-of-Trust

The 1Password operator credentials are the single manual secret. Two Kubernetes secrets are created in the `1password` namespace:

| Secret             | Key                            | Source                                      |
|--------------------|--------------------------------|---------------------------------------------|
| `op-credentials`   | `1password-credentials.json`   | `op document get` from 1Password vault      |
| `op-connect-token` | `token`                        | `op read` from 1Password vault              |

Everything else (including the 1Password operator deployment) is GitOps-managed by ArgoCD.

## Usage

```bash
./bootstrap.sh
```

## Idempotency

Every step is guarded by an existence check. The script is safe to re-run:

1. **1Password secrets** -- skipped if the secrets already exist in the `1password` namespace.
2. **ArgoCD install** -- skipped if the `argocd` namespace already exists.
3. **Root ApplicationSets** -- `kubectl apply` is naturally idempotent; always runs.
