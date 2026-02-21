# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Homelab Kubernetes configuration repo. The cluster runs Talos Linux (PXE-provisioned via Ansible), managed with a GitOps approach using ArgoCD.

Four major layers:
- **`k8s/bootstrap/`** — One-time cluster-wide setup (secrets, networking, infrastructure, CI/CD, monitoring). Run via `bootstrap.sh`.
- **`k8s/namespaces/`** — ArgoCD-managed apps, one directory per Kubernetes namespace.
- **`k8s/bases/`** — Shared Kustomize bases referenced by namespace overlays.
- **`k8s/cluster/`** — Cluster-scoped resources (PersistentVolumes).

## Required Tooling

Scripts expect these in `PATH`: `kubectl`, `kustomize`, `kfilt`, `yq`, `helm`, `jsonnet`, `jb`

## General Rules

- Always use `trash` instead of `rm` when deleting files or directories.

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
2. **Networking**: `metallb` → `ingress-nginx` → `cert-manager`
3. **Infrastructure**: `crossplane` (with HTTP provider for Cloudflare DNS)
4. **CI/CD**: `argocd` → `argowf` (Argo Workflows)
5. **Monitoring**: `prometheus-operator` + `grafana-operator`

### Namespaces (ArgoCD-managed)
Located in `k8s/namespaces/`, one directory per Kubernetes namespace:
- **`argocd/`** — ArgoCD user configurations
- **`backup-documents/`** — Kopia backup for UNAS documents (overlay of `bases/kopia`)
- **`backup-photos/`** — Kopia backup for UNAS photos (overlay of `bases/kopia`)
- **`crossplane-system/`** — Cloudflare DNS record CRDs
- **`csi-nfs/`** — CSI-NFS driver and PVs for NFS shares
- **`monitoring/`** — Grafana dashboards and datasources
- **`monitoring-uptime/`** — Kuma uptime monitoring
- **`sftp/`** — SFTP server deployment

### Shared Bases
Located in `k8s/bases/`:
- **`kopia/`** — Shared Kustomize base for Kopia backup overlays

### Cluster-Scoped Resources
Located in `k8s/cluster/`:
- **`storage/`** — NFS PersistentVolumes for UNAS shares (unas-k8s-rw, unas-docs-ro, unas-scans-rw, unas-uptime-rw)

### Configuration Patterns

**Kustomize** is the primary composition tool. Structure follows base + overlays:
```
k8s/bases/<base>/         # Shared core manifests
k8s/namespaces/<ns>/      # Namespace-specific overlays referencing bases
```

Helm charts are integrated via the `helmCharts` field in `kustomization.yaml` rather than standalone Helm releases.

**Secret injection** uses the 1Password operator — `OnePasswordItem` CRDs pull secrets from the 1Password vault into native K8s Secrets. No secrets are stored in the repo.

**`install.sh` idempotency pattern**: each bootstrap script checks if its target namespace already exists before applying anything. Safe to re-run.

### NFS Storage Layout (UNAS)
- `unas-docs-ro` — Read-only documents
- `unas-k8s-rw` — K8s cluster data (read-write)
- `unas-scans-rw` — Scanned documents
- `unas-uptime-rw` — Uptime monitoring data

### CI/CD
GitHub Actions (`.github/workflows/build.yaml`) builds container images from `/build` on push. Currently builds the `sftp` image to Docker Hub.
