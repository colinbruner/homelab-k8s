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

Four major layers:
- **`bootstrap/`** — One-time manual setup: creates 1Password root secrets, installs ArgoCD, applies the platform + apps ApplicationSets. Run via `bootstrap/bootstrap.sh`. NOT ArgoCD-managed.
- **`k8s/platform/`** — ArgoCD-managed infrastructure, ordered by sync-wave annotations (1password -30, metallb -20, cert-manager -15, gateway -10, crossplane/csi-nfs -5, storage 0).
- **`k8s/apps/`** — ArgoCD-managed services, one directory per app. Discovered by the apps ApplicationSet via a git directory generator.
- **`packages/helm/`** — Local Helm charts (postgres, cloudflare, kopia) consumed by Kustomize `helmCharts:` with `helmGlobals.chartHome`.

## Required Tooling

Scripts and CI expect these in `PATH`: `kubectl`, `kustomize`, `helm`, `kubeconform`

For 1Password secret management: `op` (1Password CLI)

Optional/utility: `kfilt`, `yq`

## General Rules

- Always use `trash` instead of `rm` when deleting files or directories.
- **Secret injection** uses the 1Password operator — `OnePasswordItem` CRDs pull secrets from the 1Password vault into native K8s Secrets. No secrets are stored in the repo.
- **Helm charts** are integrated via the `helmCharts:` field in `kustomization.yaml` with remote pinned charts. ArgoCD repo-server runs with `--enable-helm` (configured in `argocd-cm`). Local charts omit `repo` and resolve from `helmGlobals.chartHome`.

## Common Commands

### Bootstrap the cluster
```bash
# One-time setup — creates 1Password secrets, installs ArgoCD, applies ApplicationSets
./bootstrap/bootstrap.sh
```

### Build/preview a platform component
```bash
kustomize build --enable-helm k8s/platform/<component>
```

### Build/preview an app
```bash
kustomize build --enable-helm k8s/apps/<app>
```

### Dry-run / diff before applying
```bash
kustomize build --enable-helm k8s/platform/<component> | kubectl diff -f -
kustomize build --enable-helm k8s/apps/<app> | kubectl diff -f -
```

### Regenerate Cloudflare DNS manifests
```bash
bash k8s/platform/crossplane/generate.sh
```

## Architecture

### Bootstrap (one-time, manual)
`bootstrap/bootstrap.sh` performs three idempotent steps:
1. **1Password root secrets** — creates `op-credentials` and `op-connect-token` in the `1password` namespace via the `op` CLI
2. **ArgoCD install** — `kustomize build --enable-helm bootstrap/argocd | kubectl apply --server-side`
3. **GitOps root** — `kubectl apply -k bootstrap/root` (applies platform + apps ApplicationSets)

ArgoCD converges everything else.

### GitOps Wiring
Two ApplicationSets (git directory generators in `bootstrap/root/`):
- **`platform`** — generates one Application per `k8s/platform/*`, ordered by sync-wave
- **`apps`** — generates one Application per `k8s/apps/*`

Both use `automated.prune: true`, `selfHeal: true`, and `syncOptions: [CreateNamespace=true]`.

### Platform Components (`k8s/platform/`)
| Wave | Component    | Purpose                                        |
|------|------------- |------------------------------------------------|
| -30  | 1password    | 1Password Connect + operator (root-of-trust)   |
| -20  | metallb      | MetalLB load balancer                          |
| -15  | cert-manager | TLS certificate management + ClusterIssuers    |
| -10  | gateway      | Envoy Gateway, shared Gateway, TLS certs       |
|  -5  | crossplane   | Crossplane + HTTP provider + Cloudflare DNS    |
|  -5  | csi-nfs      | CSI NFS driver                                 |
|   0  | storage      | Cluster-scoped NFS PersistentVolumes           |

### Apps (`k8s/apps/`)
- **`argocd/`** — ArgoCD user configurations, RBAC, HTTPRoute
- **`backup-documents/`** — Kopia backup for UNAS documents (uses `packages/helm/kopia`)
- **`beszel/`** — Beszel monitoring agent (`dashboard.colinbruner.com`)
- **`cloudflared/`** — Cloudflare Tunnel connector (routes public traffic to Envoy Gateway)
- **`sftp/`** — SFTP server

### Local Helm Charts (`packages/helm/`)
- **`kopia/`** — Parameterized Kopia backup chart. Each backup target is a single `kopia-values.yaml` in its app overlay.
- **`cloudflare/`** — Crossplane HTTP provider Request resources for Cloudflare DNS A records.
- **`postgres/`** — Single-instance PostgreSQL StatefulSet, NFS-compatible.

### Gateway API / Ingress

The cluster uses **Envoy Gateway** with the Kubernetes Gateway API. A single shared `Gateway` resource in `k8s/platform/gateway/` terminates TLS for all domains via per-domain `Certificate` CRDs (cert-manager).

- **Gateway + Certificates**: `k8s/platform/gateway/` (ArgoCD-managed)
- **HTTPRoutes**: live in each service's app directory (e.g., `k8s/apps/argocd/`)
- **HTTP-to-HTTPS redirect**: global `HTTPRoute` in `k8s/platform/gateway/`

### Cloudflare Tunnel (Public Access)

Traffic flows: `Internet -> Cloudflare Edge -> Tunnel -> cloudflared pod -> Envoy Gateway -> App`

- **cloudflared deployment**: `k8s/apps/cloudflared/` (ArgoCD-managed)
- **DNS**: Public hostnames (`<name>.colinbruner.com`) are CNAME records pointing to the tunnel; internal hostnames (`<name>-internal.colinbruner.com`) are A records pointing to MetalLB IPs

### Exposing a New Service

To expose `foo.colinbruner.com` in namespace `foo`:

1. **Certificate** — add `k8s/platform/gateway/certificates/foo.yaml` with both public and internal SANs
2. **Gateway listener** — add `certificateRef` to `k8s/platform/gateway/gateway.yaml`
3. **Kustomization** — add cert to `k8s/platform/gateway/kustomization.yaml`
4. **HTTPRoute** — add `httproute.yaml` to `k8s/apps/foo/` with both hostnames
5. **Internal DNS** — add `foo-internal` A record to `k8s/platform/crossplane/values.yaml`, run `generate.sh`
6. **Public DNS** — run `cloudflared tunnel route dns homelab foo.colinbruner.com`
7. **Push to git** — ArgoCD syncs everything automatically

### DNS Management (Cloudflare)

**Internal A records** (Crossplane-managed, GitOps):
Defined in `k8s/platform/crossplane/values.yaml` with `-internal` suffix.
To add/change: edit `values.yaml`, run `bash k8s/platform/crossplane/generate.sh`, commit and push.

**Public CNAME records** (Cloudflare-managed):
Created via `cloudflared tunnel route dns` CLI. NOT managed via Crossplane.

IP pool: `192.168.10.240-245` (MetalLB):
- `.240-242` — Shared Envoy Gateway (all HTTPS services, internal pool)
- `.243-245` — External pool (direct LoadBalancer services, opt-in)

### NFS Storage Layout (UNAS)
- `unas-docs-ro` — Read-only documents
- `unas-k8s-rw` — K8s cluster data (read-write)
- `unas-scans-rw` — Scanned documents
- `unas-uptime-rw` — Uptime monitoring data

### CI/CD
GitHub Actions (`.github/workflows/validate.yaml`) runs on PRs and pushes to `main`:
1. **kustomize build** — renders all platform, apps, and bootstrap targets with `--enable-helm`
2. **kubeconform** — validates rendered output against Kubernetes + CRD schemas
3. **yamllint + shellcheck** — lints YAML and shell scripts
4. **ArgoCD validation** — validates `bootstrap/root` manifests against Argo CRD schemas
