# Homelab-k8s Refactor — Design Spec

**Date:** 2026-06-21
**Status:** Approved
**Scope:** Repository-wide restructure of the homelab Kubernetes GitOps repo.

## Problem

The repo bootstraps a Talos cluster and then manages it via ArgoCD, but it has
drifted across several refactors:

1. **Blurred bootstrap↔GitOps boundary.** `metallb-system`, `cert-manager`, and
   `gateway-system` exist in *both* `k8s/bootstrap/` and `k8s/namespaces/`; the
   source of truth is ambiguous.
2. **Bootstrap is ~7 scattered `install.sh` scripts**, not the single entrypoint
   intended.
3. **Vendored full Helm chart trees** are committed in-repo (`argo-cd-9.4.3/`,
   `csi-driver-nfs-4.11.0/`, `grafana-operator-5.22.0/` + `.tgz`), bloating the repo.
4. **Dead CI.** `.github/workflows/datree.yml` is the only workflow; Datree was
   shut down. There is effectively no working validation.
5. **Documentation drift.** `CLAUDE.md`/`README.md` reference `n8n`, `monitoring`,
   `monitoring-uptime` (now under `k8s/archived/`) and a `build/` directory that
   does not exist; they omit `beszel` and `garage`. Only 5 of 13 namespaces have
   READMEs.
6. **Kopia rough edges.** `kopia/kopia:latest` (with literal `TODO` comments),
   JSON config parsed with `awk`, `enableActions: false` in `repository.config`
   contradicting policy-set actions, and PV/PVC defined in the base then JSON-6902
   patched per overlay.

## Goals

- A clean, logical separation between **one-time manual bootstrap** and
  **GitOps-managed** code.
- A **Kustomize-first** directory structure with working **GitHub Actions CI**.
- Tightened configuration; **Kopia** promoted to a first-class, well-templated
  component.
- **Clear per-service documentation** with intent and operating playbooks.

## Non-goals

- No application/feature changes to running services beyond what the restructure
  requires.
- No migration to additional clusters (single-cluster layout, extensible later).
- No kind-based ArgoCD `app diff` in CI v1 (noted as a future enhancement).

---

## 1. Target repository structure

```
bootstrap/                      # one-time, manual. NOT ArgoCD-managed
  bootstrap.sh                  # single idempotent entrypoint
  argocd/                       # kustomize: argo-cd helmChart (remote, pinned)
                                #   + namespace + argocd-cm (--enable-helm)
  root/                         # platform + apps ApplicationSets (applied last)
  README.md                     # incl. the ONE manual secret step

k8s/
  platform/                     # ArgoCD-managed infra, ordered by sync-waves
    1password/                  # Connect/operator (earliest wave)
    metallb/
    cert-manager/               # chart + ClusterIssuers
    gateway/                    # envoy-gateway chart + GatewayClass + Gateway
                                #   + Certificates + http->https redirect
    crossplane/                 # chart + providers + Cloudflare DNS Requests
    csi-nfs/                    # chart + PVs
    monitoring/                 # prometheus-operator + grafana-operator (charts)
    storage/                    # cluster-scoped NFS PVs
  apps/                         # ArgoCD-managed services
    backup-documents/ backup-photos/ sftp/ ollama/ beszel/ garage/ cloudflared/ ...
  bases/                        # shared kustomize bases (non-Helm)

packages/helm/
  postgres/  cloudflare/  kopia/   # local charts
```

**Removed:** `k8s/archived/` (preserved in git history), all vendored chart
trees, the duplicated `metallb-system`/`cert-manager`/`gateway-system` copies in
the old `namespaces/` tree, and `.github/workflows/datree.yml`.

---

## 2. Bootstrap (one-time)

`bootstrap.sh` performs exactly three idempotent steps:

1. **Create the one manual secret** — 1Password Connect credentials
   (`1password-credentials.json` + token). This is the only secret that cannot be
   GitOps-managed (it is the root of trust for the 1Password operator). The script
   checks for the secret before creating it.
2. **Install ArgoCD** —
   `kustomize build --enable-helm bootstrap/argocd | kubectl apply --server-side --force-conflicts -f -`.
   The kustomization patches `argocd-cm` with `kustomize.buildOptions: --enable-helm`
   so the repo-server can render Kustomize-with-Helm sources.
3. **Apply the GitOps root** — `kubectl apply -k bootstrap/root` installs the
   `platform` and `apps` ApplicationSets.

ArgoCD converges everything else. The script is safe to re-run; each step is
guarded by an existence check.

**Prerequisites** (documented in `bootstrap/README.md`): kube-context pointed at
the target cluster with admin access; `kubectl`, `kustomize`, `helm` in `PATH`.

---

## 3. GitOps wiring & ordering

- **Two ApplicationSets**, both git directory generators:
  - `platform` → generates one Application per `k8s/platform/*`.
  - `apps` → generates one Application per `k8s/apps/*`.
- Both keep `automated.prune: true`, `selfHeal: true`, and
  `syncOptions: [CreateNamespace=true]`, matching current behavior.
- **Platform ordering** via `argocd.argoproj.io/sync-wave` annotations applied to
  generated Applications through ApplicationSet template metadata:

  | Wave | Component |
  |------|-----------|
  | -30  | 1password |
  | -20  | metallb |
  | -15  | cert-manager |
  | -10  | gateway |
  | -5   | crossplane, csi-nfs |
  | 0    | monitoring, storage |

  Apps sync at wave ≥ 0.

**Honest tradeoff (accepted):** ApplicationSet-generated Applications are not
children of a single parent app, so sync-waves are *best-effort*, not strict
cross-app ordering. ArgoCD's retry + self-heal converges transient
"CRD-not-ready-yet" failures. This avoids app-of-apps boilerplate and keeps the
design simple. If strict ordering is ever required, the two ApplicationSets can be
promoted under a root app-of-apps later without restructuring the tree.

The existing standalone `application-cronhealth.yaml` (external repo Application)
is retained, relocated under `bootstrap/root/` alongside the ApplicationSets.

---

## 4. Helm-based components

Every chart-based component is a `kustomization.yaml` using `helmCharts:` with a
remote `repo`, a **pinned `version`**, a `releaseName`, and a `valuesFile`, with
any layered CRs in `resources:`. Example:

```yaml
# k8s/platform/cert-manager/kustomization.yaml
helmCharts:
  - name: cert-manager
    repo: https://charts.jetstack.io
    version: v1.16.2
    releaseName: cert-manager
    namespace: cert-manager
    valuesFile: values.yaml
resources:
  - clusterissuer.yaml
```

ArgoCD renders these because the repo-server runs with `--enable-helm`. The same
output is reproducible locally with `kustomize build --enable-helm`. Chart
versions are visible and diffable in git; no chart trees are vendored.

Charts and pinned versions to be captured during implementation by reading the
versions currently vendored/installed (argo-cd 9.4.3, csi-driver-nfs 4.11.0,
grafana-operator 5.22.0, plus metallb, cert-manager, envoy-gateway, crossplane,
prometheus-operator). Each version is recorded from the live/vendored source — no
guessing.

---

## 5. Kopia as a first-class citizen

A new local chart `packages/helm/kopia/`. Each backup target is a single
`values.yaml` in its app overlay:

```yaml
# k8s/apps/backup-documents/kopia-values.yaml
target:
  name: documents
  sourcePath: /Volumes/Documents      # mimics the macOS path the data came from
  schedule: "15 4 * * *"
storage:
  gcsBucket: backup-unas-vol-documents-9851
chronos:
  enabled: true
```

The app overlay consumes it via Kustomize:

```yaml
# k8s/apps/backup-documents/kustomization.yaml
helmGlobals:
  chartHome: ../../../packages/helm
helmCharts:
  - name: kopia
    releaseName: backup
    namespace: backup-documents
    valuesFile: kopia-values.yaml
resources:
  - chronos.yaml          # OnePasswordItem (Chronos token)
```

Fixes baked into the chart:

- **Pinned image** (`kopia/kopia:<version>`), no `:latest`, no `TODO` comments.
- **No `awk` JSON parsing** — bucket/target/schedule passed as explicit Helm
  values and templated directly into the repository config / env.
- **`enableActions` reconciled** to `true`, consistent with the Chronos policy
  hooks.
- **Chronos before/after-snapshot health hooks** retained; token injected from an
  `OnePasswordItem`.
- **GCS credentials** continue to come from an `OnePasswordItem` (secret model
  unchanged).
- **PV/PVC templated from values** instead of base-then-JSON-6902-patch.
- Server still binds in-cluster only (reachable via its Service); the existing
  `--insecure --without-password` opt-in for kopia ≥0.23 is preserved and
  documented as an isolated-lab decision.

Backup targets migrated: `backup-documents`, `backup-photos`. Adding a new target
becomes ~2 files (a `kopia-values.yaml` + an `OnePasswordItem`).

---

## 6. CI (GitHub Actions)

A single workflow replaces `datree.yml`, triggered on pull requests and pushes to
`main`:

1. **kustomize build** — render every `k8s/platform/*`, `k8s/apps/*`, and
   `bootstrap/argocd` / `bootstrap/root` overlay with `--enable-helm` (matrix or
   loop). Fails on any build error or chart-fetch failure.
2. **kubeconform** — pipe rendered output through
   `kubeconform -strict -ignore-missing-schemas` with the CRD schema catalog
   (e.g. `datreeio/CRDs-catalog`) so operator CRs are validated.
3. **yamllint + shellcheck** — lint YAML formatting/style and shellcheck
   `bootstrap/*.sh` and any Kopia hook scripts.
4. **ArgoCD validation** — `kustomize build bootstrap/root` and kubeconform the
   generated `ApplicationSet`/`Application` manifests against the Argo CRD schemas.

kind-based ArgoCD `app diff` is explicitly out of scope for v1 to keep CI fast;
noted as a future enhancement.

---

## 7. Documentation

- **Per-component `README.md`** in every `k8s/platform/*` and `k8s/apps/*` dir,
  following a standard template:
  - **Purpose / Intent**
  - **How it works**
  - **Dependencies**
  - **Operations playbook** (deploy, restore/backup, troubleshoot, common tasks)
  - **Secrets**
- **Top-level `README.md`** rewritten: architecture overview including the
  bootstrap→GitOps flow, a service index linking every component README, and the
  "expose a new service" and "add a backup target" playbooks.
- **`CLAUDE.md`** rewritten to match the new layout: remove `n8n`/`monitoring`/
  `build/` references, add `beszel`/`garage`, document `k8s/platform/`,
  `k8s/apps/`, and `packages/helm/kopia/`.

---

## 8. Migration safety (live cluster — critical)

Both ApplicationSets use `prune: true` + `selfHeal: true`. Renaming or moving
directories changes generated Application names and can prune running workloads.
The implementation plan sequences the cutover to avoid downtime:

1. Build the new tree (`k8s/platform/`, `k8s/apps/`, `packages/helm/kopia/`) and
   `bootstrap/root/` **without removing** the old `k8s/namespaces/` tree or its
   ApplicationSet.
2. Verify the new ApplicationSets generate Applications whose rendered output
   matches live cluster state (diff, not prune) — done in CI and via
   `kustomize build` comparisons.
3. Cut over: apply the new ApplicationSets, confirm each generated app is
   `Synced`/`Healthy` against existing resources.
4. **Last:** remove the old `namespaces/` tree, the old ApplicationSet, and
   `k8s/archived/`.

Each phase is verified before the next. Because this is delivered as a PR, the
actual cutover on the live cluster is a reviewed, deliberate merge — the PR itself
does not auto-mutate the cluster until merged and synced.

---

## Implementation phases

1. **Structure & bootstrap** — new dirs, single `bootstrap.sh`, `bootstrap/argocd`,
   `bootstrap/root` ApplicationSets.
2. **Platform migration** — move/convert each infra component to
   `k8s/platform/*` with remote pinned `helmCharts`; delete vendored trees and
   duplicated namespaces copies.
3. **Apps migration** — move services to `k8s/apps/*`.
4. **Kopia chart** — `packages/helm/kopia/` + migrate `backup-documents` /
   `backup-photos`.
5. **CI** — replace `datree.yml` with the validation workflow.
6. **Docs** — per-component READMEs, top-level README, CLAUDE.md.
7. **Cleanup** — remove `k8s/archived/`, old `namespaces/` tree, old
   ApplicationSet.

Delivered as one PR for review.
