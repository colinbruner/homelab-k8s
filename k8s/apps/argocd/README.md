# ArgoCD

## Purpose

Continuous delivery for the cluster. ArgoCD watches this git repo and automatically syncs Kubernetes resources to match the desired state. It is bootstrapped via `bootstrap/bootstrap.sh` (which runs `kustomize build --enable-helm bootstrap/argocd`) and self-manages its own configuration from this directory once running.

## How it works

The ArgoCD Helm chart is installed by bootstrap. The ApplicationSets that drive GitOps live in `bootstrap/root/` (not in this directory). This directory contains the day-2 user configuration: user accounts, RBAC, Pocket ID OAuth secret, and an HTTPRoute for the web UI at `argocd.colinbruner.com`.

## Dependencies

- **gateway** -- the shared Gateway and `argocd-tls` certificate for the HTTPRoute.
- **1password** -- operator must be running for the `argocd-pocket-id-oauth` and `argocd-github-repo-creds` secrets.
- Bootstrap must have completed (ArgoCD Helm chart installed).

## Resources

- **User accounts** — `resources/argocd-users.yaml`
- **RBAC policies** — `resources/argocd-rbac.yaml`
- **HTTPRoute** — `resources/argocd-httproute.yaml` (routes `argocd.colinbruner.com` via the shared Gateway)
- **Pocket ID OAuth** — `resources/argocd-pocket-id-oauth.yaml` (OnePasswordItem for OAuth credentials)
- **GitHub repo credentials** — `resources/argocd-github-auth.yaml` (OnePasswordItem, labeled `argocd.argoproj.io/secret-type: repository`, grants ArgoCD access to the private `Bruner-Family/quant-platform` repo used by `bootstrap/root/qp-appset.yaml`)

## ApplicationSets

The ApplicationSets are defined in `bootstrap/root/`, not in this directory:

- **`bootstrap/root/apps-appset.yaml`** — a git directory generator over `k8s/apps/*`. ArgoCD automatically creates one Application per subdirectory and syncs it to the cluster.
- **`bootstrap/root/platform-appset.yaml`** — a git directory generator over `k8s/platform/*`. Manages platform-layer infrastructure services.
- **`bootstrap/root/cronhealth-app.yaml`** — the cronhealth Application.
- **`bootstrap/root/qp-appset.yaml`** — a static list generator producing `quant-platform-dev`, sourced from the private `Bruner-Family/quant-platform` repo.

**Behaviour:**
- Any new directory added under `k8s/apps/` or `k8s/platform/` is automatically picked up as a new Application.
- Sync is **automated** with `prune: true` and `selfHeal: true` — resources removed from git
  are pruned from the cluster, and out-of-band changes are reverted.
- `CreateNamespace=true` means ArgoCD will create the destination namespace if it does not exist.

**Bootstrap ordering (quant-platform):** all ApplicationSets in `bootstrap/root/` are applied in
the same `kubectl apply -k` at the end of `bootstrap.sh`, before the 1Password operator or this
`argocd` app have synced. `quant-platform-dev`'s repo credentials (`argocd-github-repo-creds`,
defined above) come from a `OnePasswordItem` that itself depends on both the 1password platform
component and this app being synced. On a fresh cluster this means the quant-platform Application
will show a repo/auth error for a few minutes. This is expected and self-resolving: each
ArgoCD Application reconciles independently, so this has no effect on the `platform` or `apps`
ApplicationSets. `automated.selfHeal` plus ArgoCD's normal reconciliation loop keep re-evaluating
the Application, and `syncPolicy.retry.limit: -1` on `qp-appset.yaml` makes sync-operation retries
unlimited (exponential backoff, capped by ArgoCD's defaults) — no manual intervention is needed
once the credentials secret materializes.

To add a new app to GitOps management, simply create a directory with a
`kustomization.yaml` under `k8s/apps/<name>/` (or `k8s/platform/<name>/` for infrastructure)
and push to `main`.

## User Accounts

User accounts are split across two resources:

- **Account definition** — declared in `argocd-cm` (`resources/argocd-users.yaml`), managed by
  ArgoCD via the ApplicationSet. Defines which accounts exist and their capabilities.
- **Passwords** — stored as bcrypt hashes in `argocd-secret` (a cluster Secret managed by
  ArgoCD). Passwords are set imperatively via the CLI and persist across syncs — ArgoCD will
  not overwrite `argocd-secret` when reconciling `argocd-cm`.

To add a new user, add an entry to `argocd-users.yaml`:
```yaml
accounts.<username>: login, apiKey   # interactive login + API token
accounts.<username>: apiKey          # API/automation token only
```

Then set their password via the CLI after pushing (see provisioning steps below).

### Defined Accounts

| Account | Capabilities | Purpose |
|---|---|---|
| `admin` | — | Built-in account, **disabled** (`admin.enabled: "false"`) |
| `colin` | `login, apiKey` | Human operator account |

---

## Initial Provisioning

A helper script `setup-users.sh` automates the steps below. It retrieves the initial admin
password from the cluster, logs in, sets the `colin` account password interactively, then
re-disables the admin account:

```bash
# Optionally override the ArgoCD hostname (defaults to argocd.colinbruner.com)
ARGOCD_HOST=argocd.colinbruner.com ./setup-users.sh
```

### Manual Steps

The built-in `admin` account is disabled in `argocd-cm`. To provision user accounts on a
fresh cluster you must temporarily re-enable it, set passwords via CLI, then disable it again.

### Step 1 — retrieve the initial admin password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

### Step 2 — temporarily re-enable the admin account

```bash
kubectl patch configmap argocd-cm -n argocd \
  --type merge -p '{"data":{"admin.enabled":"true"}}'
```

### Step 3 — port-forward and log in

If accessing via the cluster API rather than the ingress:

```bash
# Terminal 1 — keep running
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Terminal 2
argocd login localhost:8080 --username admin --password <password> --insecure
```

Or log in directly via the ingress:

```bash
argocd login argocd.colinbruner.com --grpc-web --username admin --password <password>
```

### Step 4 — set passwords for user accounts

```bash
# Set password for the 'colin' interactive account
argocd account update-password --account colin --new-password <password>
```

### Step 5 — re-disable the admin account

```bash
kubectl patch configmap argocd-cm -n argocd \
  --type merge -p '{"data":{"admin.enabled":"false"}}'
```

The next ArgoCD sync will reconcile `argocd-cm` from git, which also has `admin.enabled: "false"`,
so this is self-correcting even if you forget.

## Operations

- **Deploy:** Self-managed by ArgoCD (applicationset `apps`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n argocd
  kubectl get applications -n argocd
  kubectl get applicationsets -n argocd
  ```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `argocd-pocket-id-oauth` | (OAuth credentials) | OnePasswordItem (`vaults/lab/items/argocd-pocket-id-oauth`) |
| `argocd-github-repo-creds` | `type`, `url`, `password` (repository credentials template) | OnePasswordItem (`vaults/lab/items/ArgoCD GitHub PAT`) |
