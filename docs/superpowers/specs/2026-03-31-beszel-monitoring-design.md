# Beszel Monitoring Platform — Design Spec

## Overview

Deploy [Beszel](https://beszel.dev) as a lightweight server monitoring platform. The hub runs externally on TrueNAS (`192.168.10.50:30333`) — outside the Kubernetes cluster — due to SQLite's incompatibility with NFS storage (the only storage class available in the cluster). Stateless agents run as a DaemonSet on every cluster node, collecting host-level and container metrics and reporting back to the external hub.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Hub location | TrueNAS (`192.168.10.50:30333`) | SQLite is incompatible with NFS; TrueNAS provides local disk storage |
| Access | Public + Internal | `dashboard.colinbruner.com` via Cloudflare Tunnel, `dashboard-internal.colinbruner.com` via direct LB DNS |
| Authentication | OIDC via Pocket-ID | Configured directly on TrueNAS Beszel instance |
| Container monitoring | Yes, via containerd socket | Talos Linux uses containerd; mount socket on agents |
| Image tags | `latest` | Matches existing deployments (ollama, etc.) |
| Control plane agents | Yes, with explicit tolerations | Ensures all 9 nodes (3 control + 6 worker) are monitored |
| K8s ingress routing | Envoy Gateway → LBs → TrueNAS | LBs at `192.168.1.4` and `192.168.10.4` (port 443) provide redundancy and Host-header routing to Beszel |
| Internal DNS | Managed externally | `dashboard-internal.colinbruner.com` A record managed outside GitOps (not via Crossplane) |
| Deployment approach | Pure Kustomize | Matches majority of namespace patterns; no Helm chart overhead |
| Namespace directory | `k8s/namespaces/beszel/` | Named after the tool, consistent with `argocd/`, `ollama/`, etc. |

## Architecture

```
  Internet
     │
     ▼
  Cloudflare Edge (dashboard.colinbruner.com CNAME → homelab tunnel)
     │
     ▼
  cloudflared pod (k8s: cloudflared namespace)
     │  wildcard *.colinbruner.com → Envoy Gateway
     ▼
  Envoy Gateway / shared-gateway (gateway-system, port 443)
     │  HTTPRoute: dashboard.colinbruner.com
     │  Backend: beszel-hub Service (Endpoints: 192.168.1.4, 192.168.10.4:443)
     ▼
  Internal Load Balancers (192.168.1.4 + 192.168.10.4, port 443)
     │  Host-header routing: dashboard.colinbruner.com → Beszel
     ▼
  TrueNAS — Beszel Hub (192.168.10.50:30333)
     │  SSH (Ed25519) → node IPs :45876
     ▼
  Beszel Agents (DaemonSet, 9 pods — 3 control + 6 worker nodes)
     │  hostNetwork:true | Port 45876
     │  Mounts: /proc, /sys, containerd.sock
```

**Internal access:** `dashboard-internal.colinbruner.com` DNS A record is managed externally (outside GitOps) and points directly to the internal LBs. No Crossplane-managed record.

**Communication flow:** The hub initiates SSH connections *to* agents (not the reverse). Agents listen on `<node-ip>:45876` via `hostNetwork: true`.

## File Structure

```
k8s/namespaces/beszel/
├── kustomization.yaml
├── namespace.yaml
├── resources/
│   ├── onepassword-agent-key.yaml    # Agent SSH public key from 1Password
│   ├── hub-service.yaml              # ClusterIP Service + Endpoints → LBs (192.168.1.4, 192.168.10.4:443)
│   ├── agent-daemonset.yaml          # Agent DaemonSet on all 9 nodes
│   └── httproute.yaml                # dashboard.colinbruner.com → beszel-hub service
```

**Files in other namespaces:**

- `k8s/namespaces/gateway-system/resources/certificates/dashboard.yaml` — TLS cert (both SANs)
- `k8s/namespaces/gateway-system/resources/gateway.yaml` — `dashboard-tls` certificateRef
- `k8s/namespaces/gateway-system/kustomization.yaml` — cert in resources list
- `k8s/namespaces/cert-manager/resources/onepassword-cloudflare.yaml` — Cloudflare API token secret for DNS-01 cert issuance

**Not in GitOps:**
- Hub deployment (TrueNAS, managed outside the cluster)
- OIDC configuration (configured directly on TrueNAS Beszel instance)
- `dashboard-internal.colinbruner.com` DNS A record (managed externally)
- `dashboard.colinbruner.com` Cloudflare Tunnel CNAME (managed in Terraform)

## Component Details

### Hub (External — TrueNAS)

- **Host:** `192.168.10.50`
- **Port:** `30333`
- **Storage:** TrueNAS local disk at `/beszel_data`
- **Auth:** OIDC via Pocket-ID (configured in Beszel UI on TrueNAS)
- **Managed by:** TrueNAS Apps / Docker Compose — outside this repo

### Hub Service + Endpoints (K8s)

Provides a stable in-cluster target for the HTTPRoute. Load-balances across both LBs.

```yaml
# Service: selector-less ClusterIP on port 443
# Endpoints: 192.168.1.4 and 192.168.10.4 on port 443
```

The LBs use Host-header routing (`dashboard.colinbruner.com`) to forward to TrueNAS Beszel. The original Host header is preserved through the Envoy → LB connection.

> **Note:** Envoy Gateway sends plain HTTP to backends by default regardless of port. If the LBs require TLS on port 443, a `BackendTLSPolicy` must be added to instruct Envoy to use HTTPS for the backend connection.

### Agent DaemonSet

- **Image:** `henrygd/beszel-agent:latest`
- **hostNetwork:** `true`
- **hostPID:** `true`
- **dnsPolicy:** `ClusterFirstWithHostNet`
- **Tolerations:**
  ```yaml
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
  ```
- **Resource constraints:**
  ```yaml
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi
  ```

**Environment variables:**

| Variable | Source | Value |
|----------|--------|-------|
| `KEY` | Secret `beszel-agent-key` key `public_key` | Hub's Ed25519 public key from 1Password |
| `PORT` | Literal | `45876` |
| `DOCKER_HOST` | Literal | `unix:///run/containerd/containerd.sock` |
| `LOG_LEVEL` | Literal | `warn` |

**Host path volume mounts (all read-only):**

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `/proc` | `/host/proc` | CPU, memory, process metrics |
| `/sys` | `/host/sys` | Temperature sensors, disk info |
| `/etc/os-release` | `/host/etc/os-release` | OS identification |
| `/run/containerd/containerd.sock` | `/run/containerd/containerd.sock` | Container metrics |

### Secrets (1Password)

**`onepassword-agent-key.yaml`** — Agent SSH key (only K8s secret):
```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: beszel-agent-key
spec:
  itemPath: "vaults/lab/items/beszel-agent-key"
```

### HTTPRoute

```yaml
parentRefs:
  - name: shared-gateway
    namespace: gateway-system
    sectionName: https
hostnames:
  - dashboard.colinbruner.com
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /
    backendRefs:
      - name: beszel-hub
        port: 443
```

### TLS Certificate

File: `k8s/namespaces/gateway-system/resources/certificates/dashboard.yaml`
- SANs: `dashboard.colinbruner.com`, `dashboard-internal.colinbruner.com`
- Issuer: `letsencrypt-prod` (ClusterIssuer)
- DNS-01 challenge via Cloudflare API token in `cert-manager` namespace (`vaults/lab/items/Cloudflare`)

### DNS

- **Public:** `dashboard.colinbruner.com` — Cloudflare Tunnel CNAME, managed in Terraform
- **Internal:** `dashboard-internal.colinbruner.com` — A record managed externally, points to LBs

## Bootstrap / Operational Sequence

1. **Push to git** — ArgoCD auto-syncs beszel namespace via ApplicationSet
2. **TrueNAS:** Start Beszel hub container at port 30333, configure OIDC via Pocket-ID in the hub UI
3. **Extract SSH key:** From hub UI "Add System" dialog, copy the Ed25519 public key
4. **Store key:** Create/update `beszel-agent-key` item in 1Password `lab` vault, set `public_key` field
5. **Agents connect:** 1Password operator syncs secret → agents authenticate → hub starts collecting
6. **Register nodes:** In hub UI, add all 9 nodes using node IPs and port `45876`
7. **Verify routing:** Confirm `dashboard.colinbruner.com` routes through Cloudflare Tunnel → Envoy Gateway → LBs → TrueNAS

## Security Considerations

- **No hub secrets in repo** — OIDC and hub config managed on TrueNAS directly
- **Agent auth** — Ed25519 SSH key pair stored in 1Password, injected via operator
- **Read-only host mounts** — `/proc`, `/sys`, `/etc/os-release` mounted read-only
- **Resource limits** — agents capped at 200m CPU / 128Mi memory per node
- **Network isolation** — hub-to-agent SSH only; agents do not initiate connections
- **PodSecurity** — `beszel` namespace labeled `privileged` to permit hostNetwork/hostPID/hostPath
