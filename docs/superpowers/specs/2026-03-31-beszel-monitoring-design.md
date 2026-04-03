# Beszel Monitoring Platform — Design Spec

## Overview

Deploy [Beszel](https://beszel.dev) as a lightweight server monitoring platform on the homelab Kubernetes cluster. Beszel uses a hub + agent architecture: a single hub instance provides the web dashboard and stores historical metrics, while stateless agents run on every node to collect host-level and container metrics.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Access | Public + Internal | `dashboard.colinbruner.com` via Cloudflare Tunnel, `dashboard-internal.colinbruner.com` via Envoy Gateway |
| Authentication | OIDC via Pocket-ID | Consistent with existing cluster services; credentials from 1Password |
| Container monitoring | Yes, via containerd socket | Talos Linux uses containerd; mount socket on agents |
| Image tags | `latest` | Matches existing deployments (ollama, etc.) |
| Control plane agents | Yes, with explicit tolerations | Ensures all 9 nodes (3 control + 6 worker) are monitored |
| Hub storage | Dynamic PVC via `nfs-csi` StorageClass | Auto-provisioned NFS subdirectory; future migration target for all services |
| Deployment approach | Pure Kustomize | Matches majority of namespace patterns; no Helm chart overhead |
| Namespace directory | `k8s/namespaces/beszel/` | Named after the tool, consistent with `argocd/`, `ollama/`, etc. |

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │           Cloudflare Tunnel          │
                    │   dashboard.colinbruner.com (CNAME)  │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │         Envoy Gateway (shared)       │
                    │   dashboard-internal.colinbruner.com │
                    └──────────────┬──────────────────────┘
                                   │ HTTPRoute
                    ┌──────────────▼──────────────────────┐
                    │          Beszel Hub (Deployment)      │
                    │   Port 8090 | OIDC via Pocket-ID     │
                    │   PVC: /beszel_data (nfs-csi, 5Gi)   │
                    └──────────────┬──────────────────────┘
                                   │ SSH (Ed25519)
                    ┌──────────────▼──────────────────────┐
                    │      Beszel Agents (DaemonSet)        │
                    │   hostNetwork:true | Port 45876       │
                    │   9 pods (3 control + 6 worker)       │
                    │   Mounts: /proc, /sys, containerd.sock│
                    └─────────────────────────────────────┘
```

**Communication flow:** The hub initiates SSH connections *to* agents (not the reverse). Agents listen on `<node-ip>:45876` via `hostNetwork: true`. No agent-to-hub connectivity required.

## File Structure

```
k8s/namespaces/beszel/
├── kustomization.yaml
├── namespace.yaml
├── resources/
│   ├── onepassword-secret.yaml       # Pocket-ID OIDC credentials
│   ├── onepassword-agent-key.yaml    # Agent SSH public key
│   ├── hub-deployment.yaml           # Hub (single replica, sync-wave 0)
│   ├── hub-service.yaml              # ClusterIP on port 8090
│   ├── hub-pvc.yaml                  # 5Gi NFS-backed storage
│   ├── agent-daemonset.yaml          # Agent on all 9 nodes (sync-wave 1)
│   └── httproute.yaml                # Public + internal hostnames
```

**Files modified in other namespaces:**

- `k8s/namespaces/gateway-system/resources/certificates/dashboard.yaml` — new TLS certificate
- `k8s/namespaces/gateway-system/resources/gateway.yaml` — add `dashboard-tls` certificateRef
- `k8s/namespaces/gateway-system/kustomization.yaml` — add cert to resources list
- `k8s/namespaces/crossplane-system/values.yaml` — add `dashboard-internal` A record
- `k8s/namespaces/crossplane-system/` — regenerate via `generate.sh`

## Component Details

### Hub Deployment

- **Image:** `henrygd/beszel:latest`
- **Replicas:** 1 (SQLite is not cluster-safe)
- **Port:** 8090
- **Sync-wave:** `0` (deploy before agents)
- **Volume:** PVC mounted at `/beszel_data`
- **Probes:**
  - Liveness: `GET /` on port 8090
  - Readiness: `GET /api/health` on port 8090

**Environment variables:**

| Variable | Source | Value |
|----------|--------|-------|
| `AUTH_OIDC_CLIENT_ID` | Secret `beszel-oidc` key `client_id` | From 1Password |
| `AUTH_OIDC_CLIENT_SECRET` | Secret `beszel-oidc` key `client_secret` | From 1Password |
| `AUTH_OIDC_AUTH_URL` | Secret `beszel-oidc` key `auth_url` | From 1Password |
| `AUTH_OIDC_TOKEN_URL` | Secret `beszel-oidc` key `token_url` | From 1Password |
| `AUTH_OIDC_USER_API_URL` | Secret `beszel-oidc` key `user_api_url` | From 1Password |
| `AUTH_OIDC_DISPLAY_NAME` | Literal | `Pocket-ID` |
| `AUTH_OIDC_REDIRECT_URL` | Literal | `https://dashboard.colinbruner.com/api/oauth2-redirect` |
| `DISABLE_PASSWORD_AUTH` | Literal | `false` (set to `true` after OIDC confirmed working) |
| `USER_CREATION` | Literal | `false` |

### Hub Service

- **Type:** ClusterIP
- **Port:** 8090 → 8090

### Hub PVC

- **StorageClass:** `nfs-csi`
- **Access mode:** `ReadWriteOnce`
- **Size:** 5Gi
- **Mount path:** `/beszel_data`

### Agent DaemonSet

- **Image:** `henrygd/beszel-agent:latest`
- **Sync-wave:** `1` (deploy after hub)
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

**`onepassword-secret.yaml`** — OIDC credentials:
```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: beszel-oidc
spec:
  itemPath: "vaults/lab/items/beszel-oidc"
```

**`onepassword-agent-key.yaml`** — Agent SSH key:
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
  - dashboard-internal.colinbruner.com
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /
    backendRefs:
      - name: beszel-hub
        port: 8090
```

### TLS Certificate

New file at `k8s/namespaces/gateway-system/resources/certificates/dashboard.yaml`:
- SANs: `dashboard.colinbruner.com`, `dashboard-internal.colinbruner.com`
- Added as `dashboard-tls` certificateRef in the shared gateway HTTPS listener

### DNS

- **Internal:** `dashboard-internal` A record added to `k8s/namespaces/crossplane-system/values.yaml`, regenerated via `generate.sh`
- **Public:** `cloudflared tunnel route dns homelab dashboard.colinbruner.com` (manual CLI command)

## Bootstrap Sequence

1. **Push to git** — ArgoCD auto-syncs via ApplicationSet
2. **Wave 0:** Hub deployment starts, creates SQLite DB and generates SSH key pair in `/beszel_data`
3. **Wave 1:** Agent DaemonSet starts, agents fail SSH auth (expected — key not yet in 1Password)
4. **Initial setup:** Access hub UI at `dashboard.colinbruner.com`, complete OIDC login
5. **Extract SSH key:** From hub UI "Add System" dialog, copy the Ed25519 public key
6. **Store key:** Create `beszel-agent-key` item in 1Password `lab` vault with `public_key` field
7. **Agents connect:** 1Password operator syncs secret → agents pick up key → SSH auth succeeds
8. **Register nodes:** In hub UI, add all 9 nodes using their node IPs and port 45876
9. **Lock down:** Set `DISABLE_PASSWORD_AUTH=true` in hub deployment once OIDC is confirmed working

## Security Considerations

- **No secrets in repo** — all credentials via 1Password operator
- **OIDC authentication** — Pocket-ID SSO, password auth disabled after setup
- **User registration disabled** — `USER_CREATION=false`
- **Agent auth** — Ed25519 SSH key pair, no passwords
- **Read-only host mounts** — `/proc`, `/sys`, `/etc/os-release` mounted read-only
- **Resource limits** — agents capped at 200m CPU / 128Mi memory per node
- **Network isolation** — hub-to-agent only, agents do not initiate connections
