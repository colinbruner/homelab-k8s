# Homelab-k8s Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the repo into a minimal one-time `bootstrap/` and a Kustomize-first, ArgoCD-managed `k8s/platform/` + `k8s/apps/` tree, with Kopia as a local Helm chart, working CI, and per-service docs.

**Architecture:** `bootstrap.sh` installs only ArgoCD (+ the manual 1Password root secret) and applies two ApplicationSets (`platform`, `apps`). All infra and apps are rendered via Kustomize, with Helm charts pulled from pinned remote repos (`--enable-helm`). Migration is additive-then-cutover to protect the live cluster.

**Tech Stack:** Kustomize (with `--enable-helm`), Helm (remote charts), ArgoCD ApplicationSets, kubeconform, yamllint, shellcheck, GitHub Actions.

## Global Constraints

- **LF line endings only.** Never CRLF.
- **Use `trash`, never `rm`**, for deletions.
- **No guessing paths/versions.** Read the source file named in each task.
- **Pinned chart versions** (read from current bootstrap install scripts — verified values below):
  | Component | Source | Repo / ref | Version |
  |-----------|--------|-----------|---------|
  | argo-cd | `bootstrap/argocd` | `https://argoproj.github.io/argo-helm` | `9.4.3` |
  | 1password connect | `secrets/1password/install.sh` | `https://1password.github.io/connect-helm-charts/` | chart `connect` (pin latest at impl) |
  | metallb | `network/01-metal-lb/kustomization.yml` | `github.com/metallb/metallb/config/native` | `v0.15.3` (kustomize remote, NOT helm) |
  | gateway-api CRDs | `network/02-gateway/install.sh` | `kubernetes-sigs/gateway-api` standard-install | `v1.2.1` |
  | envoy-gateway | `network/02-gateway/install.sh` | `oci://docker.io/envoyproxy/gateway-helm` | `v1.7.0` |
  | cert-manager | `network/03-cert-manager/install.sh` | `https://charts.jetstack.io` | `v1.16.2` |
  | crossplane | `infra/crossplane/install.sh` | `https://charts.crossplane.io/stable` | unpinned today — pin at impl |
  | csi-driver-nfs | `k8s/namespaces/csi-nfs/kustomization.yaml` | (read repo from that file) | `4.11.0` |
  | prometheus/grafana operators | `bootstrap/monitoring/` (jsonnet today) | see Task 8 | pin at impl |
- **Verification is the test.** For every Kustomize dir touched, the "test" is:
  `kustomize build --enable-helm <dir> | kubeconform -strict -ignore-missing-schemas -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'`
  Must exit 0 before commit.
- **Migration safety:** do NOT delete `k8s/namespaces/` or its ApplicationSet until Task 13. New trees are added alongside the old until cutover.
- **Commit after every task.** Co-author trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## Phase 1 — Tooling & CI foundation

### Task 1: CI workflow (replace datree)

**Files:**
- Create: `.github/workflows/validate.yaml`
- Create: `.yamllint.yaml`
- Delete: `.github/workflows/datree.yml`

**Interfaces:**
- Produces: a reusable `make`-free validation that later tasks rely on locally:
  the kubeconform command in Global Constraints.

- [ ] **Step 1: Write `.yamllint.yaml`** — relaxed ruleset (document-start disabled, line-length 160, indentation consistent), excluding `packages/helm/*/templates/` and `**/charts/`.

- [ ] **Step 2: Write `.github/workflows/validate.yaml`** with four jobs, triggered on `pull_request` and `push: branches: [main]`:
  - `kustomize-build`: install kustomize + helm; loop over `bootstrap/argocd`, `bootstrap/root`, `k8s/platform/*`, `k8s/apps/*`; run `kustomize build --enable-helm` on each; fail on error. Skip dirs without `kustomization.yaml`.
  - `kubeconform`: same loop, pipe through the kubeconform command from Global Constraints.
  - `lint`: run `yamllint .` and `shellcheck $(git ls-files '*.sh')`.
  - `argocd-validate`: `kustomize build bootstrap/root` piped through kubeconform with Argo schema location added.
  Use `continue-on-error: false`. Since `k8s/platform`/`k8s/apps` don't exist yet, guard the loops so an empty glob passes (no failure when dirs are absent).

- [ ] **Step 3: Verify locally** — `yamllint .github/workflows/validate.yaml .yamllint.yaml` exits 0. Run `shellcheck` on existing `*.sh` to capture the current baseline (note failures; they're fixed in their owning tasks).

- [ ] **Step 4: Delete datree** — `trash .github/workflows/datree.yml`.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "ci: replace dead datree workflow with kustomize/kubeconform/lint validation"`.

---

## Phase 2 — Bootstrap

### Task 2: `bootstrap/argocd` (Kustomize + remote Helm)

**Files:**
- Create: `bootstrap/argocd/kustomization.yaml`
- Create: `bootstrap/argocd/values.yaml` (port from `k8s/bootstrap/argocd/values.yaml`)
- Create: `bootstrap/argocd/namespace.yaml` (from `k8s/bootstrap/argocd/resources/namespace.yaml`)
- Create: `bootstrap/argocd/argocd-cm-patch.yaml`

**Interfaces:**
- Produces: a namespace `argocd` with ArgoCD installed and `kustomize.buildOptions: --enable-helm` set in `argocd-cm`.

- [ ] **Step 1:** Read `k8s/bootstrap/argocd/values.yaml` and `k8s/bootstrap/argocd/kustomization.yaml`; copy values verbatim to `bootstrap/argocd/values.yaml`.

- [ ] **Step 2:** Write `bootstrap/argocd/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - namespace.yaml
helmCharts:
  - name: argo-cd
    repo: https://argoproj.github.io/argo-helm
    version: 9.4.3
    releaseName: argo-cd
    namespace: argocd
    valuesFile: values.yaml
patches:
  - path: argocd-cm-patch.yaml
    target:
      kind: ConfigMap
      name: argocd-cm
```

- [ ] **Step 3:** Write `argocd-cm-patch.yaml` adding `data.kustomize.buildOptions: --enable-helm`. (If the chart doesn't emit `argocd-cm`, instead add it as a resource ConfigMap merged by name — verify by rendering.)

- [ ] **Step 4: Verify** — `kustomize build --enable-helm bootstrap/argocd | kubeconform ...` exits 0; confirm rendered output contains `--enable-helm` in `argocd-cm`.

- [ ] **Step 5: Commit** — `git commit -m "feat(bootstrap): argocd via kustomize remote helm chart with --enable-helm"`.

### Task 3: `bootstrap/root` ApplicationSets

**Files:**
- Create: `bootstrap/root/kustomization.yaml`
- Create: `bootstrap/root/platform-appset.yaml`
- Create: `bootstrap/root/apps-appset.yaml`
- Create: `bootstrap/root/cronhealth-app.yaml` (port from `k8s/namespaces/argocd/resources/application-cronhealth.yaml`)

**Interfaces:**
- Consumes: directory globs `k8s/platform/*` and `k8s/apps/*` (created in later phases).
- Produces: two ApplicationSets named `platform` and `apps`.

- [ ] **Step 1:** Write `platform-appset.yaml` — git directory generator over `k8s/platform/*`, repoURL `https://github.com/colinbruner/homelab-k8s`, template app name `{{path.basename}}`, destination namespace `{{path.basename}}`, `syncPolicy.automated{prune,selfHeal}`, `syncOptions: [CreateNamespace=true]`, and template metadata annotation `argocd.argoproj.io/sync-wave` driven by a per-path value. Since the git generator can't compute waves per-dir, set waves via a `goTemplate: true` ApplicationSet with a `map` of basename→wave (1password:-30, metallb:-20, cert-manager:-15, gateway:-10, crossplane:-5, csi-nfs:-5, monitoring:0, storage:0); default 0.

- [ ] **Step 2:** Write `apps-appset.yaml` — git directory generator over `k8s/apps/*`, same policy, no special waves (default 0).

- [ ] **Step 3:** Write `cronhealth-app.yaml` from the existing file verbatim.

- [ ] **Step 4:** Write `bootstrap/root/kustomization.yaml` listing all three.

- [ ] **Step 5: Verify** — `kustomize build bootstrap/root | kubeconform -strict -ignore-missing-schemas -schema-location default -schema-location '<argo CRD schema>'` exits 0.

- [ ] **Step 6: Commit** — `git commit -m "feat(bootstrap): platform + apps ApplicationSets with sync-wave ordering"`.

### Task 4: Single `bootstrap.sh`

**Files:**
- Create: `bootstrap/bootstrap.sh` (executable)
- Create: `bootstrap/README.md`

**Interfaces:**
- Consumes: `bootstrap/argocd`, `bootstrap/root`.

- [ ] **Step 1:** Write `bootstrap/bootstrap.sh` (`#!/bin/bash -euo pipefail`) doing three idempotent steps:
  1. Ensure 1Password root secret(s): if the `1password` namespace/credentials secret is absent, create namespace and the credentials + connect-token secrets from 1Password CLI (`op read`/`op document get`) — port the secret-creation portion of `k8s/bootstrap/secrets/1password/install.sh`. Guard with existence check.
  2. Install ArgoCD: if namespace `argocd` absent → `kustomize build --enable-helm bootstrap/argocd | kubectl apply --server-side --force-conflicts -f -`; then `kubectl -n argocd rollout status deploy/argo-cd-argocd-repo-server`.
  3. Apply GitOps root: `kubectl apply -k bootstrap/root`.
  Use absolute `SCRIPTPATH` resolution like the existing scripts.

- [ ] **Step 2:** `chmod +x bootstrap/bootstrap.sh`.

- [ ] **Step 3:** Write `bootstrap/README.md` — prerequisites (kube-context, `kubectl`/`kustomize`/`helm`, `op` CLI), the one manual secret explained, run instructions, idempotency note.

- [ ] **Step 4: Verify** — `shellcheck bootstrap/bootstrap.sh` exits 0; `bash -n bootstrap/bootstrap.sh` parses.

- [ ] **Step 5: Commit** — `git commit -m "feat(bootstrap): single idempotent bootstrap.sh (argocd + root appsets)"`.

---

## Phase 3 — Platform migration

> For each platform task: create `k8s/platform/<name>/`, port resources from the named sources, write a `README.md` (Task 12 template can be applied inline now or in Phase 6 — write at least a stub Purpose). Verify with the Global Constraints kubeconform command. Do NOT delete old sources yet.

### Task 5: `platform/1password`

**Files:**
- Create: `k8s/platform/1password/kustomization.yaml`, `values.yaml`, `namespace.yaml`, `README.md`

- [ ] **Step 1:** Read `k8s/bootstrap/secrets/1password/install.sh` and `resources/namespace.yaml`. The Deployment (connect + operator) becomes GitOps; the credentials secret stays manual (created by `bootstrap.sh`, Task 4).

- [ ] **Step 2:** Write `kustomization.yaml` with `helmCharts:` for `connect` from `https://1password.github.io/connect-helm-charts/` (pin the current chart version — read `helm search repo 1password/connect --versions` and pin newest). Set values so the chart **references the existing manually-created credentials secret** rather than creating it (`operator.create=true`, `operator.token.value` sourced from existing secret, `connect.credentials` omitted). **Verify the chart supports an existing-secret reference by rendering;** if it cannot, fall back to keeping the full `helm install connect` in `bootstrap.sh` and make `platform/1password` contain only the namespace + a README documenting that. Record the chosen approach in the README.

- [ ] **Step 3: Verify** render + kubeconform.

- [ ] **Step 4: Commit** — `git commit -m "feat(platform): 1password connect/operator as GitOps component"`.

### Task 6: `platform/metallb`

**Files:**
- Create: `k8s/platform/metallb/kustomization.yaml`, `README.md`
- Port: IPAddressPool + L2Advertisement from `k8s/namespaces/metallb-system/resources/`

- [ ] **Step 1:** Read `k8s/namespaces/metallb-system/resources/*` and `k8s/bootstrap/network/01-metal-lb/kustomization.yml`.

- [ ] **Step 2:** Write `kustomization.yaml`: `namespace: metallb-system`, resources = `github.com/metallb/metallb/config/native?ref=v0.15.3` plus the ported IPAddressPool/L2Advertisement CRs.

- [ ] **Step 3: Verify** render + kubeconform (`-ignore-missing-schemas` covers MetalLB CRs).

- [ ] **Step 4: Commit** — `git commit -m "feat(platform): metallb (native config + address pools)"`.

### Task 7: `platform/cert-manager` and `platform/gateway`

**Files:**
- Create: `k8s/platform/cert-manager/{kustomization.yaml,values.yaml,README.md}` + ported ClusterIssuers
- Create: `k8s/platform/gateway/{kustomization.yaml,values.yaml,README.md}` + ported GatewayClass/Gateway/Certificates/redirect

- [ ] **Step 1:** Read `k8s/namespaces/cert-manager/resources/*` (ClusterIssuers) and `k8s/bootstrap/network/03-cert-manager/install.sh`.
- [ ] **Step 2:** cert-manager `kustomization.yaml`: helmChart `cert-manager` repo `https://charts.jetstack.io` version `v1.16.2`, values `crds.enabled: true`; resources = ported ClusterIssuers.
- [ ] **Step 3:** Read `k8s/namespaces/gateway-system/resources/*` (gateway.yaml, certificates/, redirect HTTPRoute, EnvoyPatchPolicy if present), `k8s/bootstrap/network/02-gateway/{install.sh,helm-values.yaml,resources/}`.
- [ ] **Step 4:** gateway `kustomization.yaml`: helmChart from `oci://docker.io/envoyproxy/gateway-helm` version `v1.7.0` with `helm-values.yaml` (`config.extensionApis.enableEnvoyPatchPolicy: true`); resources = GatewayClass, namespace, Gateway, Certificates, redirect route. **Gateway API CRDs** (`v1.2.1`) are not in any chart — add as a remote resource `github.com/kubernetes-sigs/gateway-api/config/crd/standard?ref=v1.2.1` (verify path renders) or document them as a bootstrap kubectl-apply step in the README if the kustomize remote path is unavailable.
- [ ] **Step 5: Verify** both render + kubeconform.
- [ ] **Step 6: Commit** — `git commit -m "feat(platform): cert-manager + envoy gateway as GitOps components"`.

### Task 8: `platform/crossplane`, `platform/csi-nfs`, `platform/monitoring`, `platform/storage`

**Files:**
- Create each `k8s/platform/<name>/{kustomization.yaml,values.yaml?,README.md}`

- [ ] **Step 1 — crossplane:** Read `k8s/namespaces/crossplane-system/` (values.yaml, generate.sh, resources/cloudflare/, provider + providerconfig) and `infra/crossplane/install.sh`. Write helmChart `crossplane` repo `https://charts.crossplane.io/stable` (pin newest stable via `helm search repo`); resources = provider-http, ProviderConfig http-cloudflare, and the generated Cloudflare DNS `Request` resources. Preserve `generate.sh` + `values.yaml` workflow (move them into this dir).
- [ ] **Step 2 — csi-nfs:** Read `k8s/namespaces/csi-nfs/kustomization.yaml` for the chart repo; rewrite to remote `helmCharts` (csi-driver-nfs `4.11.0`) instead of vendored `charts/`. Port the NFS PVs from `resources/`.
- [ ] **Step 3 — monitoring:** Current monitoring is jsonnet-based (`bootstrap/monitoring/prometheus/build/`) and the namespace overlay is archived. Per spec, establish operator-only: helmCharts for `prometheus-operator` (repo `https://prometheus-community.github.io/helm-charts`, chart `kube-prometheus-stack` OR standalone `prometheus-operator` — choose standalone operator to match spec; pin version) and `grafana-operator` (read version from `k8s/archived/monitoring/charts/grafana-operator-5.22.0`, repo `ghcr.io/grafana/helm-charts` OCI; pin `5.22.0`). **In the README, flag that this replaces the jsonnet kube-prometheus stack and dashboards/rules must be reconciled by a human during cutover.**
- [ ] **Step 4 — storage:** Move `k8s/cluster/storage/*` PVs into `k8s/platform/storage/` with a `kustomization.yaml`.
- [ ] **Step 5: Verify** each renders + kubeconform.
- [ ] **Step 6: Commit** — `git commit -m "feat(platform): crossplane, csi-nfs, monitoring operators, storage"`.

---

## Phase 4 — Kopia local Helm chart

### Task 9: `packages/helm/kopia` chart

**Files:**
- Create: `packages/helm/kopia/Chart.yaml`, `values.yaml`, `templates/{deployment.yaml,service.yaml,pv.yaml,pvc.yaml,password.yaml,_helpers.tpl}`, `README.md`
- Reference: `k8s/bases/kopia/*` (existing base — port logic), `docs/superpowers/specs/2026-06-21-kopia-chronos-design.md`

**Interfaces:**
- Produces: a chart consumed via `helmCharts: [{name: kopia, releaseName: backup}]` with `values.yaml` shape:
  `target.{name,sourcePath,schedule}`, `storage.gcsBucket`, `chronos.enabled`, `image.{repository,tag}`, `resources`, `persistence.{size,...}`.

- [ ] **Step 1:** Read `k8s/bases/kopia/{deployment.yaml,service.yaml,pv.yaml,pvc.yaml,password.yaml,actions/*}` and both overlays' `patches/` + `config/repository.config`.

- [ ] **Step 2:** Write `Chart.yaml` (apiVersion v2, name kopia) and `values.yaml` with the interface shape above; **pin `image.tag`** to a real released kopia tag (read current running tag if available, else latest stable release — no `:latest`).

- [ ] **Step 3:** Write `templates/deployment.yaml` porting init + server containers, with these fixes: bucket/target/schedule come from `.Values` (no `awk` JSON parsing — render `repository.config` from a template or pass `--bucket {{ .Values.storage.gcsBucket }}` directly); `enableActions: true`; Chronos before/after hooks gated by `.Values.chronos.enabled`; preserve the `--insecure --without-password --allow-extremely-dangerous-unauthenticated-server-on-the-network` server flags with the explanatory comment. Mount the GCS credentials from the `gcp-credentials` secret and Chronos token from the `chronos` secret as today.

- [ ] **Step 4:** Write `service.yaml`, `pv.yaml`, `pvc.yaml`, `password.yaml`, `_helpers.tpl`, and bundle the `chronos-start.sh`/`chronos-success.sh` action scripts (as a templated ConfigMap from `.Files` or inline).

- [ ] **Step 5: Verify** — `helm template backup packages/helm/kopia --set target.name=test --set storage.gcsBucket=x | kubeconform ...` exits 0; `shellcheck` the action scripts.

- [ ] **Step 6: Commit** — `git commit -m "feat(kopia): local helm chart (pinned image, no awk, actions enabled)"`.

### Task 10: Migrate backup-documents & backup-photos to `apps/`

**Files:**
- Create: `k8s/apps/backup-documents/{kustomization.yaml,kopia-values.yaml,chronos.yaml,README.md}`
- Create: `k8s/apps/backup-photos/{kustomization.yaml,kopia-values.yaml,chronos.yaml,README.md}`

- [ ] **Step 1:** From `k8s/namespaces/backup-documents/`, derive `kopia-values.yaml`: `target.name=documents`, `sourcePath=/Volumes/Documents`, `schedule="15 4 * * *"`, `storage.gcsBucket=backup-unas-vol-documents-9851`, `chronos.enabled=true`. Port `chronos.yaml` OnePasswordItem verbatim. Repeat for photos (read its `config/repository.config` + `patches/deployment.yaml` for bucket and sourcePath).

- [ ] **Step 2:** Write each `kustomization.yaml` with `helmGlobals.chartHome: ../../../packages/helm` + `helmCharts: [{name: kopia, releaseName: backup, namespace: <ns>, valuesFile: kopia-values.yaml}]` + `resources: [chronos.yaml]` + the namespace resource.

- [ ] **Step 3: Verify** — `kustomize build --enable-helm k8s/apps/backup-documents | kubeconform ...` exits 0; diff rendered Deployment against the OLD `kustomize build k8s/namespaces/backup-documents` to confirm functional parity (image, mounts, env, bucket).

- [ ] **Step 4: Commit** — `git commit -m "feat(apps): migrate backup-documents/photos to kopia helm chart"`.

---

## Phase 5 — Apps migration

### Task 11: Move remaining services to `apps/`

**Files (per service: move dir, fix relative paths):**
- `k8s/apps/sftp/` ← `k8s/namespaces/sftp/`
- `k8s/apps/ollama/` ← `k8s/namespaces/ollama/`
- `k8s/apps/beszel/` ← `k8s/namespaces/beszel/`
- `k8s/apps/garage/` ← `k8s/namespaces/garage/`
- `k8s/apps/cloudflared/` ← `k8s/namespaces/cloudflared/`

- [ ] **Step 1:** For each service, `git mv k8s/namespaces/<svc> k8s/apps/<svc>`. Read each `kustomization.yaml` and fix any relative paths to `../../bases/...` or `../../../packages/helm` (depth unchanged: `namespaces`→`apps` is same depth, so relative paths to `k8s/bases` and `packages/helm` are unchanged — verify each renders).
- [ ] **Step 2:** Keep `argocd` configs: move `k8s/namespaces/argocd/` → `k8s/apps/argocd/` BUT remove `application-cronhealth.yaml` and `applicationset.yaml` (now in `bootstrap/root/`). Keep RBAC, users, httproute, oauth.
- [ ] **Step 3: Verify** — `for d in k8s/apps/*; do kustomize build --enable-helm $d | kubeconform ...; done` all exit 0.
- [ ] **Step 4: Commit** — `git commit -m "refactor(apps): relocate services from namespaces/ to apps/"`.

---

## Phase 6 — Documentation

### Task 12: Per-component READMEs

**Files:** `README.md` in every `k8s/platform/*` and `k8s/apps/*` (any missing one).

**Template (each section required, concise):**
```markdown
# <name>
## Purpose
## How it works
## Dependencies
## Operations
- Deploy: managed by ArgoCD (applicationset `platform`/`apps`).
- Troubleshoot: <commands>
- Backup/Restore (if applicable):
- Common tasks:
## Secrets
```

- [ ] **Step 1:** Write/complete a README for each component using the template. For backup-* include restore-from-GCS playbook (kopia repository connect + restore).
- [ ] **Step 2:** Carry over content from existing source READMEs (argocd, cloudflared, crossplane-system, csi-nfs, gateway-system) where useful.
- [ ] **Step 3: Verify** — `yamllint` unaffected; spot-check links.
- [ ] **Step 4: Commit** — `git commit -m "docs: per-component READMEs with operating playbooks"`.

### Task 13: Top-level README + CLAUDE.md rewrite

**Files:** Modify `README.md`, `CLAUDE.md`; create `docs/architecture.md` (optional).

- [ ] **Step 1:** Rewrite top-level `README.md`: architecture + bootstrap→GitOps flow, service index linking every component README, "expose a new service" and "add a backup target" playbooks.
- [ ] **Step 2:** Rewrite `CLAUDE.md`: new `k8s/platform/` + `k8s/apps/` layout, `packages/helm/kopia`, remove `n8n`/`monitoring`/`build/` references, add `beszel`/`garage`. Update "Required Tooling" and "Common Commands".
- [ ] **Step 3:** Update `TODO.md` if relevant (or leave).
- [ ] **Step 4: Commit** — `git commit -m "docs: rewrite README and CLAUDE.md for new layout"`.

---

## Phase 7 — Cutover & cleanup

### Task 14: Remove old tree

**Files:** Delete (via `trash`): `k8s/namespaces/`, `k8s/bootstrap/`, `k8s/archived/`, `k8s/cluster/` (after storage moved), and any stale `k8s/bases/kopia` if fully superseded by the chart.

- [ ] **Step 1:** Confirm every component now exists under `bootstrap/`, `k8s/platform/`, `k8s/apps/`, or `packages/helm/` (checklist against the original tree). Confirm the `apps`/`platform` ApplicationSets reference only the new paths.
- [ ] **Step 2:** `trash k8s/namespaces k8s/bootstrap k8s/archived`. Move/remove `k8s/cluster/storage` (now `platform/storage`) and `k8s/bases/kopia` (now the chart) — verify nothing else references them via grep first.
- [ ] **Step 3: Verify** — full CI commands locally: `for d in bootstrap/argocd bootstrap/root k8s/platform/* k8s/apps/*; do kustomize build --enable-helm $d | kubeconform ...; done` all exit 0; `yamllint .`; `shellcheck $(git ls-files '*.sh')`.
- [ ] **Step 4: Commit** — `git commit -m "refactor: remove legacy bootstrap/namespaces/archived trees"`.

### Task 15: Final verification & PR

- [ ] **Step 1:** Run the full CI suite locally one more time (all four checks).
- [ ] **Step 2:** Push branch `refactor/gitops-structure`.
- [ ] **Step 3:** Open PR with summary, the migration-safety note (cutover is a deliberate post-merge ArgoCD sync), and a reviewer checklist (verify each app renders to parity with live state before syncing).

---

## Self-review notes

- **Spec coverage:** §1 structure → Tasks 2–11,14; §2 bootstrap → Tasks 2–4; §3 wiring/waves → Task 3; §4 helm strategy → Tasks 2,5–8; §5 kopia → Tasks 9–10; §6 CI → Task 1; §7 docs → Tasks 12–13; §8 migration safety → additive ordering + Task 14 cutover + Task 15 PR note. ✅
- **Known decision points flagged for implementer:** 1Password existing-secret reference (Task 5), Gateway API CRD remote-kustomize path (Task 7), crossplane/monitoring version pinning + jsonnet→operator monitoring change (Task 8). Each has an explicit fallback.
- **Verification is uniform:** the kubeconform command in Global Constraints is the test for every Kustomize/Helm dir.
