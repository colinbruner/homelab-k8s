# CLAUDE.md

## Approach
- Think before acting. Read existing files before writing code.
- Be concise in output but thorough in reasoning.
- Prefer editing over rewriting whole files.
- Do not re-read files you have already read unless the file may have changed.
- Test your code before declaring done.
- No sycophantic openers or closing fluff.
- Keep solutions simple and direct. No over-engineering.
- If unsure: say so. Never guess or invent file paths.
- User instructions always override this file.

## Efficiency
- Read before writing. Understand the problem before coding.
- No redundant file reads. Read each file once.
- One focused coding pass. Avoid write-delete-rewrite cycles.
- Test once, fix if needed, verify once. No unnecessary iterations.
- Budget: 50 tool calls maximum. Work efficiently.

## Overview

Homelab Kubernetes configuration repo. The cluster runs Talos Linux (PXE-provisioned via Ansible), managed with a GitOps approach using ArgoCD.

Five major layers:
- **`k8s/bootstrap/`** — One-time cluster-wide setup: installs operators, CRDs, and Helm charts only. Run via `bootstrap.sh`. No application-level resources (routes, certs, CRs) belong here.
- **`k8s/namespaces/`** — ArgoCD-managed apps and configuration, one directory per Kubernetes namespace. All day-2 operational changes go here.
- **`k8s/bases/`** — Shared Kustomize bases referenced by namespace overlays.
- **`k8s/cluster/`** — Cluster-scoped resources (PersistentVolumes).
- **`packages/`** — Reusable local Helm charts consumed by namespace kustomizations via `helmGlobals.chartHome`.

## Required Tooling

Scripts expect these in `PATH`: `kubectl`, `kustomize`, `kfilt`, `yq`, `helm`, `jsonnet`, `jb`

## General Rules

- Always use `trash` instead of `rm` when deleting files or directories.
- **Bootstrap installs operators/controllers only.** All application-level resources (HTTPRoutes, Certificates, Grafana CRs, etc.) belong in `k8s/namespaces/` where ArgoCD manages them.

## Common Commands

### Bootstrap the cluster
```bash
# Run from k8s/bootstrap/ — idempotently installs all components
./bootstrap.sh
```

### Apply Kustomize manifests
```bash
kustomize build k8s/namespaces/<namespace> | kubectl apply -f -
```

### Dry-run / diff before applying
```bash
kustomize build k8s/namespaces/<namespace> | kubectl diff -f -
```

### Build Prometheus manifests from Jsonnet
```bash
# From k8s/bootstrap/monitoring/prometheus/build/
jb install
jsonnet -J vendor main.jsonnet | gojsonyaml > manifests.yaml
```

### Build and push container images
Container builds are handled by GitHub Actions on changes to `/build`. To build locally:
```bash
docker build -f build/<name>/Containerfile -t <image> build/<name>/
```

## Architecture

### Bootstrap Components (installed once, in order)
1. **Secrets**: `1password` operator + `external-secrets`
2. **Networking**: `metallb` → `envoy-gateway` (Helm + GatewayClass) → `cert-manager`
3. **Infrastructure**: `crossplane` (with HTTP provider for Cloudflare DNS)
4. **CI/CD**: `argocd` (Helm chart + namespace only)
5. **Monitoring**: `prometheus-operator` + `grafana-operator` (Helm only)

### Namespaces (ArgoCD-managed)
Located in `k8s/namespaces/`, one directory per Kubernetes namespace:
- **`argocd/`** — ArgoCD user configurations, RBAC, ApplicationSet, HTTPRoute
- **`backup-documents/`** — Kopia backup for UNAS documents (overlay of `bases/kopia`)
- **`backup-photos/`** — Kopia backup for UNAS photos (overlay of `bases/kopia`)
- **`crossplane-system/`** — Cloudflare DNS A records (all records, managed via Helm template + generate.sh)
- **`csi-nfs/`** — CSI-NFS driver and PVs for NFS shares
- **`gateway-system/`** — Shared Gateway, TLS Certificates, HTTP-to-HTTPS redirect
- **`monitoring/`** — Grafana CR, secrets, dashboards, datasources, HTTPRoutes for Grafana and Prometheus
- **`monitoring-uptime/`** — Kuma uptime monitoring
- **`n8n/`** — n8n workflow automation
- **`ollama/`** — Ollama LLM deployment
- **`sftp/`** — SFTP server deployment
- **`cloudflared/`** — Cloudflare Tunnel connector (routes public internet traffic to Envoy Gateway)

### Shared Bases
Located in `k8s/bases/`:
- **`kopia/`** — Shared Kustomize base for Kopia backup overlays

### Local Helm Charts
Located in `packages/helm/`, one subdirectory per chart. Consumed by namespace
`kustomization.yaml` files via:
```yaml
helmGlobals:
  chartHome: ../../../packages/helm   # relative path to packages/helm/ from k8s/namespaces/<ns>/

helmCharts:
  - name: postgres    # matches packages/helm/postgres/
    releaseName: postgres
    namespace: <ns>
    valuesFile: postgres-values.yaml
```

Available charts:
- **`postgres/`** — Single-instance PostgreSQL StatefulSet, NFS-compatible (configurable
  `securityContext`/`fsGroup`, `PGDATA` subdirectory, pg_hba.conf). Used by `n8n`.
- **`cloudflare/`** — Crossplane HTTP provider `Request` resources for Cloudflare DNS A records.

### Cluster-Scoped Resources
Located in `k8s/cluster/`:
- **`storage/`** — NFS PersistentVolumes for UNAS shares (unas-k8s-rw, unas-docs-ro, unas-scans-rw, unas-uptime-rw)

### Configuration Patterns

**Kustomize** is the primary composition tool. Structure follows base + overlays:
```
k8s/bases/<base>/         # Shared core manifests
k8s/namespaces/<ns>/      # Namespace-specific overlays referencing bases
```

Helm charts are integrated via the `helmCharts` field in `kustomization.yaml` rather than standalone Helm releases. Remote charts specify a `repo` URL; local charts omit `repo` and are resolved from `helmGlobals.chartHome` (pointing to `packages/helm/`).

**Secret injection** uses the 1Password operator — `OnePasswordItem` CRDs pull secrets from the 1Password vault into native K8s Secrets. No secrets are stored in the repo.

**`install.sh` idempotency pattern**: each bootstrap script checks if its target namespace already exists before applying anything. Safe to re-run.

### Gateway API / Ingress

The cluster uses **Envoy Gateway** with the Kubernetes Gateway API. A single shared `Gateway` resource in `gateway-system` terminates TLS for all domains via per-domain `Certificate` CRDs (cert-manager).

- **Gateway + Certificates**: `k8s/namespaces/gateway-system/` (ArgoCD-managed)
- **HTTPRoutes**: live in each service's namespace directory (e.g., `k8s/namespaces/argocd/resources/argocd-httproute.yaml`)
- **HTTP-to-HTTPS redirect**: global `HTTPRoute` in `gateway-system`

### Cloudflare Tunnel (Public Access)

Public internet access uses a **Cloudflare Tunnel** via `cloudflared` pods. Traffic flows:
`Internet → Cloudflare Edge → Tunnel → cloudflared pod → Envoy Gateway → App`

- **cloudflared deployment**: `k8s/namespaces/cloudflared/` (ArgoCD-managed)
- **Tunnel config**: ConfigMap with wildcard ingress rule pointing to Envoy Gateway proxy service
- **DNS**: Public hostnames (`<name>.colinbruner.com`) are CNAME records pointing to the tunnel; internal hostnames (`<name>-internal.colinbruner.com`) are A records pointing to MetalLB IPs
- **Setup docs**: See `k8s/namespaces/cloudflared/README.md` for full manual setup steps

### Exposing a New Service

To expose `foo.colinbruner.com` in namespace `foo`:

1. **Certificate** — add `k8s/namespaces/gateway-system/resources/certificates/foo.yaml` with both public and internal SANs (`foo.colinbruner.com` + `foo-internal.colinbruner.com`)
2. **Gateway listener** — add `certificateRef` to `k8s/namespaces/gateway-system/resources/gateway.yaml`
3. **Kustomization** — add cert to `k8s/namespaces/gateway-system/kustomization.yaml`
4. **HTTPRoute** — add `httproute.yaml` to `k8s/namespaces/foo/` with both hostnames
5. **Internal DNS** — add `foo-internal` A record to `k8s/namespaces/crossplane-system/values.yaml`, run `generate.sh`
6. **Public DNS** — run `cloudflared tunnel route dns homelab foo.colinbruner.com`
7. **Push to git** — ArgoCD syncs everything automatically

### DNS Management (Cloudflare)

Two types of DNS records:

**Internal A records** (Crossplane-managed, GitOps):
Defined in `k8s/namespaces/crossplane-system/values.yaml` with `-internal` suffix.
Managed by ArgoCD via Crossplane HTTP provider `Request` CRDs.

To add or change an internal DNS record:
1. Edit `k8s/namespaces/crossplane-system/values.yaml`
2. Run `bash k8s/namespaces/crossplane-system/generate.sh`
3. Commit and push — ArgoCD syncs the change

**Public CNAME records** (Cloudflare-managed):
Point `<name>.colinbruner.com` to `<TUNNEL_ID>.cfargotunnel.com`.
Created via `cloudflared tunnel route dns` CLI or the Cloudflare dashboard.
These are NOT managed via Crossplane (tunnel CNAME records are outside GitOps).

IP pool: `192.168.10.240–245` (MetalLB). Currently:
- `.240–242` — Shared Envoy Gateway (all HTTPS services, internal pool)
- `.243–245` — External pool (direct LoadBalancer services, opt-in)

### NFS Storage Layout (UNAS)
- `unas-docs-ro` — Read-only documents
- `unas-k8s-rw` — K8s cluster data (read-write)
- `unas-scans-rw` — Scanned documents
- `unas-uptime-rw` — Uptime monitoring data

### CI/CD
GitHub Actions (`.github/workflows/build.yaml`) builds container images from `/build` on push. Currently builds the `sftp` image to Docker Hub.
