# Cloudflare Tunnel (cloudflared)

## Purpose

Routes public internet traffic into the cluster through a Cloudflare Tunnel, eliminating the
need for any open inbound ports on the home network. Public hostnames resolve to a tunnel
CNAME; `cloudflared` connects outbound to Cloudflare and forwards matched traffic to the
shared Envoy Gateway (or, for Proxmox, directly to the PVE nodes).

## Dependencies

- **gateway** — the shared Envoy Gateway that cloudflared forwards `*.colinbruner.com` to.
- **1password** — operator must be running to provision the `cloudflared-tunnel` secret
  (`vaults/lab/items/cloudflared-tunnel`), injected as `TUNNEL_TOKEN`.
- **cert-manager** — issues the TLS certificates the Gateway terminates.

## Architecture

```
Internet
    |
    v
Cloudflare Edge (TLS termination, DDoS, WAF, bot protection)
    |  (Cloudflare Tunnel — encrypted QUIC/HTTP2)
    v
cloudflared pods (k8s, 2 replicas)
    |
    +-- pve.colinbruner.com  --> Proxmox VE nodes (192.168.10.11-13:8006), bypasses Gateway
    |
    +-- *.colinbruner.com    --> Envoy Gateway (shared-gateway :443, noTLSVerify)
                                     |
                                     +-- HTTPRoute (hostname match) --> app Service --> pod
```

Routing is defined in `resources/configmap.yaml`. Only hostnames that have a Cloudflare DNS
CNAME pointing at the tunnel actually reach `cloudflared` — that CNAME is the access control.

See [docs/ingress-traffic-flow.md](../../../docs/ingress-traffic-flow.md) for the full
public + internal flow, including the LAN path that bypasses Cloudflare.

### Traffic flow (public, via tunnel)

```
User --> argocd.colinbruner.com
     --> Cloudflare Edge (CNAME to <TUNNEL_ID>.cfargotunnel.com)
     --> Tunnel (encrypted)
     --> cloudflared pod
     --> Envoy Gateway (HTTPS, noTLSVerify)
     --> HTTPRoute --> argo-cd-argocd-server
```

### Traffic flow (internal/LAN, direct)

```
User --> argocd-internal.colinbruner.com
     --> DNS A record (192.168.10.240-242, MetalLB)
     --> Envoy Gateway (HTTPS, TLS terminated with Let's Encrypt cert)
     --> HTTPRoute --> argo-cd-argocd-server
```

## DNS naming convention

| Access path         | DNS pattern                       | Record type | Target                         |
| ------------------- | --------------------------------- | ----------- | ------------------------------ |
| **Public** (tunnel) | `<name>.colinbruner.com`          | CNAME       | `<TUNNEL_ID>.cfargotunnel.com` |
| **Internal** (LAN)  | `<name>-internal.colinbruner.com` | A           | `192.168.10.240-242`           |

Public CNAME records are created via the Cloudflare dashboard or `cloudflared tunnel route
dns`. Internal A records are managed via Terraform (Cloudflare, outside this repo).

## Manual setup (Cloudflare dashboard)

### 1. Create a Cloudflare Tunnel

1. Log in to the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/).
2. Navigate to **Networks > Tunnels** and **Create a tunnel** (connector type **Cloudflared**).
3. Name it (e.g. `homelab`) and save the credentials. You'll get a **tunnel token**.
4. **Do not configure public hostnames in the dashboard** — routing is managed by the local
   config file in `resources/configmap.yaml`.

### 2. Store the tunnel token in 1Password

Create a 1Password item at `vaults/lab/items/cloudflared-tunnel` with a `token` field set to
the tunnel token. The OnePasswordItem CRD creates a Kubernetes Secret whose `token` is
injected as `TUNNEL_TOKEN` (token-based auth — no credentials file needed).

### 3. Set the tunnel ID in the ConfigMap

Edit `resources/configmap.yaml` and set the `tunnel:` field to your tunnel UUID.

### 4. Create DNS CNAME records

Because we use a locally-managed config file (not the dashboard), CNAME records are not
created automatically:

```bash
cloudflared tunnel login   # one-time, downloads ~/.cloudflared/cert.pem
cloudflared tunnel route dns homelab argocd.colinbruner.com
cloudflared tunnel route dns homelab dashboard.colinbruner.com
cloudflared tunnel route dns homelab pve.colinbruner.com
```

Each command creates `<hostname> -> <TUNNEL_ID>.cfargotunnel.com`. A hostname cannot have
both an A and a CNAME record, so make sure any old A record for the public name is removed.

## Exposing a new public service

To expose `foo.colinbruner.com` (namespace `foo`):

1. **Certificate** — add `k8s/platform/gateway/certificates/foo.yaml` with both public and
   internal SANs (`foo.colinbruner.com`, `foo-internal.colinbruner.com`).
2. **Gateway listener** — add the `certificateRef` to `k8s/platform/gateway/gateway.yaml`.
3. **Kustomization** — add the cert file to `k8s/platform/gateway/kustomization.yaml`.
4. **HTTPRoute** — add `httproute.yaml` in `k8s/apps/foo/` with both hostnames.
5. **Internal DNS** — add a `foo-internal` A record (MetalLB Gateway IP) via the Terraform
   Cloudflare config and apply it.
6. **Public DNS** — `cloudflared tunnel route dns homelab foo.colinbruner.com`.
7. **Push to git** — ArgoCD syncs everything automatically.

## Security notes

- **No open inbound ports**: all public traffic flows outbound through the tunnel.
- **Internal separation**: LAN clients use `*-internal.colinbruner.com` A records pointing at
  MetalLB IPs, bypassing Cloudflare entirely.
- **Edge protections**: Cloudflare provides TLS termination, WAF, DDoS, and bot management.
- **Pod-to-Gateway**: cloudflared connects to Envoy over HTTPS with `noTLSVerify`; the
  Gateway re-terminates TLS with the Let's Encrypt cert.
- **Authentication is per-app**: ArgoCD uses its own RBAC. There is currently no centralized
  forward-auth (ext_authz) layer at the Gateway.

## Troubleshooting

```bash
# Tunnel status / logs
kubectl get pods -n cloudflared
kubectl logs -n cloudflared -l app=cloudflared --tail=50

# Tunnel metrics
kubectl port-forward -n cloudflared deploy/cloudflared 2000:2000
curl http://localhost:2000/metrics

# Verify the Envoy proxy service name cloudflared targets
kubectl get svc -n envoy-gateway-system

# DNS checks
dig argocd.colinbruner.com CNAME
dig argocd-internal.colinbruner.com A

# Certificate status
kubectl get certificates -n gateway
kubectl describe certificate argocd-tls -n gateway
```

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `apps`). Synced from this directory.
- **Verify:** See Troubleshooting above.

## Secrets

| Secret               | Key     | Source                                                  |
| -------------------- | ------- | ------------------------------------------------------- |
| `cloudflared-tunnel` | `token` | OnePasswordItem (`vaults/lab/items/cloudflared-tunnel`) |
