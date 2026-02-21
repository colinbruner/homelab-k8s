# ArgoCD

ArgoCD is bootstrapped via `k8s/bootstrap/argocd/` and self-manages its own configuration
from this directory once running.

## ApplicationSet

`resources/applicationset.yaml` defines a `namespaces` ApplicationSet that uses the Git
directory generator to watch `k8s/namespaces/` in this repo. ArgoCD automatically creates
one Application per subdirectory and syncs it to the cluster.

**Behaviour:**
- Any new directory added under `k8s/namespaces/` is automatically picked up as a new Application.
- Sync is **automated** with `prune: true` and `selfHeal: true` — resources removed from git
  are pruned from the cluster, and out-of-band changes are reverted.
- `CreateNamespace=true` means ArgoCD will create the destination namespace if it does not exist.

To add a new namespace/app to GitOps management, simply create a directory with a
`kustomization.yaml` under `k8s/namespaces/<name>/` and push to `main`.

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
| `crossplane` | `apiKey` | Automation account for Crossplane |

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

# Generate an API token for the 'crossplane' automation account
argocd account generate-token --account crossplane
```

Store the `crossplane` token wherever it is consumed (e.g. a 1Password vault item).

### Step 5 — re-disable the admin account

```bash
kubectl patch configmap argocd-cm -n argocd \
  --type merge -p '{"data":{"admin.enabled":"false"}}'
```

The next ArgoCD sync will reconcile `argocd-cm` from git, which also has `admin.enabled: "false"`,
so this is self-correcting even if you forget.
