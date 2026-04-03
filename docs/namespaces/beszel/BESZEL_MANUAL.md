# Beszel Manual Setup Steps

These steps must be performed after the manifests are pushed and ArgoCD has synced.

## Prerequisites

- `cloudflared` CLI authenticated to the Cloudflare account
- Access to the 1Password `lab` vault
- `kubectl` access to the cluster

## Step 1: Create Pocket-ID OIDC Client

In your Pocket-ID admin UI, create a new OIDC client for Beszel:

1. Navigate to your Pocket-ID instance (e.g. `https://pocket-id.colinbruner.com`)
2. Go to OIDC Clients and create a new client
3. Set the following:
   - **Name:** Beszel
   - **Redirect URI:** `https://dashboard.colinbruner.com/api/oauth2-redirect`
4. Save and note the generated Client ID and Client Secret

## Step 2: Create 1Password Item — `beszel-oidc`

In the 1Password `lab` vault, create an item named exactly `beszel-oidc` with these fields:

| Field | Example Value |
|-------|---------------|
| `client_id` | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| `client_secret` | `s3cr3t-k3y-fr0m-p0ck3t-1d` |
| `auth_url` | `https://pocket-id.colinbruner.com/authorize` |
| `token_url` | `https://pocket-id.colinbruner.com/api/oidc/token` |
| `user_api_url` | `https://pocket-id.colinbruner.com/api/oidc/userinfo` |

The field names must match exactly — they correspond to the `secretKeyRef` keys in `resources/hub-deployment.yaml`.

Verify the item path matches the OnePasswordItem manifest:
```
vaults/lab/items/beszel-oidc
```

## Step 3: Create 1Password Item — `beszel-agent-key`

In the 1Password `lab` vault, create an item named exactly `beszel-agent-key` with one field:

| Field | Value |
|-------|-------|
| `public_key` | *(leave empty for now — populated in Step 6)* |

Verify the item path matches the OnePasswordItem manifest:
```
vaults/lab/items/beszel-agent-key
```

## Step 4: Register Public DNS via Cloudflare Tunnel

```bash
cloudflared tunnel route dns homelab dashboard.colinbruner.com
```

This creates a CNAME record pointing `dashboard.colinbruner.com` to the `homelab` tunnel. Verify:

```bash
dig dashboard.colinbruner.com CNAME +short
# Expected: <tunnel-id>.cfargotunnel.com.
```

## Step 5: Push Manifests and Wait for ArgoCD Sync

```bash
git push origin main
```

Monitor the sync in ArgoCD:
- The `beszel` application should appear automatically (ApplicationSet auto-discovery)
- The `gateway-system` application will sync the new TLS certificate
- The `crossplane-system` application will sync the new DNS A record

Check hub pod status:
```bash
kubectl -n beszel get pods
# Expected: beszel-hub-xxx Running (agents may be in CrashLoopBackOff — expected until Step 6)
```

The hub pod may show warnings about the `beszel-oidc` secret not existing yet. The 1Password operator needs a few minutes to sync the secret after the item is created. If the pod stays in `CreateContainerConfigError`, check:

```bash
kubectl -n beszel describe pod -l app=beszel-hub
kubectl -n beszel get secrets
# Verify beszel-oidc and beszel-agent-key secrets exist
```

## Step 6: Extract SSH Public Key and Store in 1Password

1. Access the hub UI at `https://dashboard.colinbruner.com` or `https://dashboard-internal.colinbruner.com`

2. Complete initial setup:
   - Click the "Pocket-ID" OIDC login button
   - Authenticate via Pocket-ID
   - Your account is created as the first (admin) user

3. Extract the SSH public key:
   - Click **"Add System"** in the hub UI
   - The dialog displays the hub's Ed25519 public key, e.g.:
     ```
     ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBzBp3oFsnMwjiNYMCj5MnRdh5sFgPOxJkVZKMwgVbXB
     ```
   - Copy this entire key string

4. Update the 1Password item:
   - Open `beszel-agent-key` in the 1Password `lab` vault
   - Set the `public_key` field to the copied SSH public key
   - Save

5. Wait for the 1Password operator to sync (~1-2 minutes):
   ```bash
   # Watch for the secret to update
   kubectl -n beszel get secret beszel-agent-key -o jsonpath='{.data.public_key}' | base64 -d
   # Should output the SSH public key you just stored
   ```

6. The agent pods will automatically pick up the key and connect to the hub. If they're in CrashLoopBackOff, they'll restart and succeed on the next cycle.

   ```bash
   kubectl -n beszel get pods -l app=beszel-agent
   # Expected: 9 pods Running (one per node)
   ```

## Step 7: Register All 9 Nodes in the Hub

In the hub UI, add each node as a system. You'll need the node IPs:

```bash
kubectl get nodes -o wide --no-headers | awk '{print $1, $6}'
```

For each node:
1. Click **"Add System"** in the hub UI
2. Enter:
   - **Name:** the node hostname (e.g., `control-01`, `worker-01`)
   - **Host:** the node's internal IP (e.g., `192.168.10.101`)
   - **Port:** `45876`
3. Click **Save**
4. Verify metrics start appearing within 30 seconds

Repeat for all 3 control plane nodes and 6 worker nodes (9 total).

## Step 8: Disable Password Authentication

Once OIDC login is confirmed working:

1. Edit `k8s/namespaces/beszel/resources/hub-deployment.yaml`
2. Change:
   ```yaml
           - name: DISABLE_PASSWORD_AUTH
             value: "false"
   ```
   to:
   ```yaml
           - name: DISABLE_PASSWORD_AUTH
             value: "true"
   ```
3. Commit and push:
   ```bash
   git add k8s/namespaces/beszel/resources/hub-deployment.yaml
   git commit -m "feat(beszel): disable password auth after OIDC confirmed"
   git push origin main
   ```
4. ArgoCD will sync the change and restart the hub pod.

## Verification Checklist

After all steps are complete:

- [ ] `https://dashboard.colinbruner.com` loads the Beszel UI
- [ ] `https://dashboard-internal.colinbruner.com` loads the Beszel UI
- [ ] OIDC login via Pocket-ID works
- [ ] All 9 nodes show as connected in the hub
- [ ] CPU, memory, disk, and network metrics are populating
- [ ] Password authentication is disabled
- [ ] Container metrics from containerd are visible (if supported)

## Troubleshooting

**Hub pod won't start (CreateContainerConfigError):**
```bash
kubectl -n beszel describe pod -l app=beszel-hub
kubectl -n beszel get secrets
```
The `beszel-oidc` secret must exist. Check that the 1Password item name and vault path match exactly.

**Agents stuck in CrashLoopBackOff:**
```bash
kubectl -n beszel logs -l app=beszel-agent --tail=20
```
Most likely the `beszel-agent-key` secret is missing or the `public_key` field is empty. Complete Step 6.

**No container metrics:**
Containerd support in Beszel may be limited. If container stats don't appear, you can disable it by removing the `DOCKER_HOST` env var from `resources/agent-daemonset.yaml` and pushing the change.

**Certificate not issued:**
```bash
kubectl -n gateway-system get certificate dashboard-tls
kubectl -n gateway-system describe certificate dashboard-tls
```
Ensure the cert-manager ClusterIssuer `letsencrypt-prod` is working and DNS is resolvable.

**DNS not resolving (internal):**
```bash
dig dashboard-internal.colinbruner.com +short
# Expected: 192.168.10.240, .241, .242
```
Check that the Crossplane resources synced: `kubectl -n crossplane-system get requests | grep dashboard`
