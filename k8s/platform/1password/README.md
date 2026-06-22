# 1Password Connect + Operator

Deploys the 1Password Connect server and Kubernetes operator via the
`1password/connect` Helm chart, managed by ArgoCD.

## Purpose

The operator watches for `OnePasswordItem` custom resources and pulls secrets
from the `homelab` vault into native Kubernetes `Secret` objects. Services
across the cluster use `OnePasswordItem` CRDs to declaratively request secrets
without storing credentials in git.

## Root-of-Trust Secrets

Two secrets must exist in the `1password` namespace **before** this component
is synced. They are the manual root-of-trust created by
`bootstrap/bootstrap.sh` and are **not** stored in git:

| Secret              | Key                           | Source                          |
|---------------------|-------------------------------|---------------------------------|
| `op-credentials`    | `1password-credentials.json`  | 1Password vault document export |
| `op-connect-token`  | `token`                       | 1Password Connect access token  |

The Helm chart references these existing secrets; it does not recreate them.
