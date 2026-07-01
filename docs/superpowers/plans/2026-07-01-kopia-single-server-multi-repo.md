# Kopia Backup Refactor — Multi-Source, Multi-Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `packages/helm/kopia` from one-server-per-backup-target into a chart that renders one hardened, TLS+authenticated Kopia server **per repository** (each repository = one storage bucket, GCS or S3), with a `sources[]` list where each source maps to a repository and gets its own NFS PV/PVC, cron schedule, retention policy, and Chronos token — then deploy it as a new `k8s/apps/backup/` app.

**Architecture:** The chart gains two top-level lists: `repositories[]` (each entry renders a Deployment + Service + cert-manager Certificate + scripts ConfigMap + config PVC + verify CronJob) and `sources[]` (each entry renders a ReadOnlyMany NFS PV/PVC and a bootstrap-applied kopia policy on the server of the repository it references). Snapshot scheduling is Kopia's built-in scheduler (`--snapshot-time-crontab` policies owned by the server's stable `user@host` identity) — no k8s CronJobs for snapshots; the only CronJob is monthly `kopia snapshot verify` per repository. Bootstrap is an initContainer running a ConfigMap-mounted `set -euo pipefail` script: connect-or-create, idempotent `kopia policy set` per source, pinned maintenance ownership. This amends spec §3.7: instead of forcing one repository, the chart supports N repositories with sources mapped individually; the production overlay still starts with one (the existing GCS bucket).

**Tech Stack:** Helm (local chart via Kustomize `helmCharts:`), Kustomize, kubeconform, cert-manager (new `selfsigned` ClusterIssuer), 1Password operator, kopia/kopia:0.23.1, bash.

**Spec:** `docs/kopia-refactor-spec.md` (amended per above). Decisions locked with user:
- Backends: **GCS + S3** (S3 covers AWS/B2/MinIO/Wasabi via endpoint).
- Identity: **keep `root@kopia`** for the existing documents repository (zero-touch lineage); identity is per-repository values.
- Cache: **NFS `nfs-csi` PVC** (`/app/cache` + `/app/config` on one PVC per repository).
- Old app `k8s/apps/backup-documents/`: **deleted manually after live verification** (runbook in Task 11), NOT in this plan's commits.

## Global Constraints

- Image pinned: `kopia/kopia:0.23.1`. Server port: `51515` (Kopia default).
- The flags `--insecure`, `--without-password`, `--allow-extremely-dangerous-unauthenticated-server-on-the-network` must not appear anywhere in the new chart.
- Existing GCS bucket reused verbatim: `backup-unas-vol-documents-9851`. Documents source keeps `mountPath: /Volumes/Documents` and identity `root@kopia` (snapshot lineage).
- PV names are cluster-scoped; the existing cluster already has a PV named `backup-documents`, so new source PVs are named `<namespace>-src-<source>` (e.g. `backup-src-documents`) — no collision.
- No secrets in the repo; all secrets are `OnePasswordItem` CRDs.
- Use `trash` (never `rm`) to delete files. LF line endings.
- Every task must keep these green: `kustomize build --enable-helm` for all of `bootstrap/argocd`, `bootstrap/root`, `k8s/platform/*`, `k8s/apps/*`; kubeconform (`-strict -ignore-missing-schemas -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'`); `yamllint .`; `shellcheck -S error` on all tracked `*.sh`.
- The still-running `backup-documents` app must stay renderable throughout — Task 1 freezes the old chart as `packages/helm/kopia-legacy` before the refactor begins.
- Deviations from spec (already vetted): probes are `tcpSocket` not `httpGet` (Kopia returns 401 without basic auth, which fails httpGet probes); TLS issuer is a new `selfsigned` ClusterIssuer (the platform only has Let's Encrypt issuers, which cannot issue for `*.svc.cluster.local`); OnePasswordItems live in the app overlay, not chart templates (itemPaths are environment-specific).

## Manual Prerequisites (human, before merge/sync — see runbook from Task 11)

1Password vault `lab` items to create/extend (the operator materializes them; nothing in-cluster to do now):
- `Kopia Server` — fields `password`, `control-password` (new).
- `Chronos Backup` — one field per source name (`documents`) + one per repo verify job (`verify-primary`), each holding a Chronos ping token (new item; per-source tokens created in Chronos first).
- `GCP Backup Service Account` — field `sa_json` holding the existing GCS service-account JSON (fixes spec S4; currently a manually created secret).
- `UNAS Backup Password` — already exists, reused as the repository password.

---

### Task 1: Freeze the legacy chart so the old app keeps rendering

The refactor rewrites `packages/helm/kopia` in place. `k8s/apps/backup-documents` (still deployed) consumes it, so first copy the chart to `packages/helm/kopia-legacy` and repoint the old overlay. Note: the `helm.sh/chart` label changes, so ArgoCD will do one benign Recreate rollout of the old backup server.

**Files:**
- Create: `packages/helm/kopia-legacy/` (copy of `packages/helm/kopia/`)
- Modify: `packages/helm/kopia-legacy/Chart.yaml`
- Modify: `k8s/apps/backup-documents/kustomization.yaml`

**Interfaces:**
- Produces: chart `kopia-legacy` in `packages/helm/`, consumed only by `k8s/apps/backup-documents`. Frees `packages/helm/kopia` for the rewrite in Tasks 2–9.

- [ ] **Step 1: Copy the chart**

```bash
cp -R packages/helm/kopia packages/helm/kopia-legacy
```

- [ ] **Step 2: Rename the copied chart**

In `packages/helm/kopia-legacy/Chart.yaml` change only the `name:` line:

```yaml
name: kopia-legacy
```

- [ ] **Step 3: Repoint the old overlay**

In `k8s/apps/backup-documents/kustomization.yaml` change the helm chart name:

```yaml
helmCharts:
  - name: kopia-legacy
    releaseName: backup
    namespace: backup-documents
    valuesFile: kopia-values.yaml
```

- [ ] **Step 4: Verify the old app still renders and validates**

Run:
```bash
kustomize build --enable-helm k8s/apps/backup-documents > /tmp/legacy.yaml
grep -c 'kind: Deployment' /tmp/legacy.yaml           # expected: 1
grep 'helm.sh/chart: kopia-legacy' /tmp/legacy.yaml | head -1   # expected: label present
kubeconform -strict -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  < /tmp/legacy.yaml
```
Expected: Deployment present, label present, kubeconform exits 0.

- [ ] **Step 5: Commit**

```bash
git add packages/helm/kopia-legacy k8s/apps/backup-documents/kustomization.yaml
git commit -m "chore(kopia): freeze legacy chart as kopia-legacy for backup-documents"
```

---

### Task 2: New chart interface — values, helpers, validation, test harness

Gut the chart: new `values.yaml` (repositories/sources lists), rewritten `_helpers.tpl`, a render-time validation template, fixtures, and a grep-based render test script. All old templates and scripts are deleted; subsequent tasks add templates back one at a time, each preceded by failing assertions.

**Files:**
- Modify: `packages/helm/kopia/Chart.yaml`
- Modify: `packages/helm/kopia/values.yaml` (full replace)
- Modify: `packages/helm/kopia/templates/_helpers.tpl` (full replace)
- Create: `packages/helm/kopia/templates/validation.yaml`
- Create: `packages/helm/kopia/tests/render-test.sh`
- Create: `packages/helm/kopia/tests/fixtures/single-gcs.yaml`
- Create: `packages/helm/kopia/tests/fixtures/multi-backend.yaml`
- Create: `packages/helm/kopia/tests/fixtures/bad-repo-ref.yaml`
- Delete: `packages/helm/kopia/templates/{deployment,service,pv,pvc,configmap-repository,configmap-actions,password}.yaml`, `packages/helm/kopia/files/chronos-start.sh`, `packages/helm/kopia/files/chronos-success.sh`, `packages/helm/kopia/README.md` content is rewritten later (leave file, Task 9 replaces it)

**Interfaces:**
- Produces (consumed by every later task):
  - Helper `kopia.labels` (context: `$`) — common labels.
  - Helper `kopia.repoFullname` (context: `dict "root" $ "repo" $repo`) — `<release>-<repoName>`.
  - Helper `kopia.repoSelectorLabels` (same dict context) — name/instance/component selector labels.
  - Helper `kopia.validateSources` (context: `$`) — fails render on unknown `source.repository` or missing `source.retention`.
  - Helper `kopia.repoEnv` (context: `dict "root" $ "repo" $repo` + optional key `"usernameOverride"`) — TZ, `KOPIA_CONFIG_PATH=/app/config/repository.config`, `KOPIA_LOG_DIR=/tmp/kopia-logs`, `KOPIA_CACHE_SIZE_MB`, `KOPIA_OVERRIDE_USERNAME`, `KOPIA_OVERRIDE_HOSTNAME`, `KOPIA_PASSWORD` (secretKeyRef), plus backend env.
  - Helper `kopia.backendEnv` (same dict) — `REPO_TYPE` + `GCS_BUCKET`/`GCS_CREDENTIALS_FILE` or `S3_BUCKET`/`S3_ENDPOINT`/`S3_REGION`/`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`.
  - Helper `kopia.repoStateMounts` (same dict) — mounts `state`→`/app`, `scripts`→`/app/scripts` (RO), `tmp`→`/tmp`, and for GCS `gcs-credentials`→`/credentials/gcs` (RO).
  - Helper `kopia.backendVolumes` (same dict) — for GCS, the `gcs-credentials` secret volume (key `sa_json` → `credentials.json`).
  - Test harness `tests/render-test.sh` with `assert_contains FILE SUBSTRING DESC`, `assert_not_contains FILE SUBSTRING DESC`, `assert_count FILE REGEX N DESC`; renders fixtures to `$out/single.yaml` and `$out/multi.yaml`; later tasks insert assertions between the `# ---- assertions ----` markers.

- [ ] **Step 1: Delete old templates and scripts**

```bash
trash packages/helm/kopia/templates/deployment.yaml \
      packages/helm/kopia/templates/service.yaml \
      packages/helm/kopia/templates/pv.yaml \
      packages/helm/kopia/templates/pvc.yaml \
      packages/helm/kopia/templates/configmap-repository.yaml \
      packages/helm/kopia/templates/configmap-actions.yaml \
      packages/helm/kopia/templates/password.yaml \
      packages/helm/kopia/files/chronos-start.sh \
      packages/helm/kopia/files/chronos-success.sh
```

- [ ] **Step 2: Update Chart.yaml**

Replace `packages/helm/kopia/Chart.yaml` with:

```yaml
apiVersion: v2
name: kopia
description: >
  Multi-source, multi-repository Kopia backup for the homelab cluster.
  Each entry in repositories[] renders one hardened TLS+authenticated
  Kopia server (Deployment/Service/Certificate/config PVC/verify CronJob)
  against one storage bucket (GCS or S3). Each entry in sources[] maps an
  NFS share to a repository with its own schedule, retention, and Chronos
  token. Snapshot scheduling runs inside the Kopia server.
type: application
version: 2.0.0
appVersion: "0.23.1"
```

- [ ] **Step 3: Write the new values.yaml**

Replace `packages/helm/kopia/values.yaml` with:

```yaml
image:
  repository: kopia/kopia
  tag: "0.23.1"
  pullPolicy: IfNotPresent

timezone: America/Chicago

# One Kopia repository server per entry (Deployment + Service + Certificate +
# scripts ConfigMap + config PVC + verify CronJob). Sources reference a
# repository by name; sources sharing a repository share deduplication.
repositories: []
# - name: primary
#   backend:
#     type: gcs                        # gcs | s3
#     gcs:
#       bucket: my-bucket
#       credentialsSecret: gcp-credentials   # key: sa_json
#     # s3:
#     #   bucket: my-bucket
#     #   endpoint: s3.us-east-1.amazonaws.com
#     #   region: us-east-1                   # optional
#     #   credentialsSecret: aws-credentials  # keys: access_key_id, secret_access_key
#   identity:                          # stable user@host owning all sources + maintenance
#     username: kopia
#     hostname: backup
#   passwordSecret:
#     name: backup                     # repository password secret
#     key: password
#   cacheSizeMB: 5000
#   configSize: 20Gi                   # nfs-csi PVC holding kopia config + cache

# Backup sources. Each produces a static ReadOnlyMany NFS PV/PVC and a kopia
# policy (schedule, retention, compression, chronos actions) applied at
# bootstrap on the referenced repository's server. Retention is required;
# omitted fields mean "keep none" — kopia's implicit defaults never apply.
sources: []
# - name: documents
#   repository: primary
#   mountPath: /Volumes/Documents
#   nfsPath: /var/nfs/shared/Documents
#   schedule: "15 4 * * *"
#   retention:
#     latest: 3
#     hourly: 0
#     daily: 14
#     weekly: 8
#     monthly: 12
#     annual: 2
#   chronos: true
#   capacity: 1Ti                      # optional; defaults to nfs.defaultCapacity

server:
  port: 51515
  uiUsername: kopia
  controlUsername: server-control

nfs:
  server: "192.168.10.5"
  defaultCapacity: "1Ti"

tls:
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer

verify:
  enabled: true
  schedule: "30 6 1 * *"    # monthly, off-peak
  filesPercent: 1
  fileParallelism: 4

chronos:
  enabled: true
  pingBase: "https://chronos.bruner.family/ping"

secrets:
  server:
    name: kopia-server      # keys: password, control-password
  chronos:
    name: chronos           # one key per source name + verify-<repository>

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  fsGroup: 65532
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

- [ ] **Step 4: Write the new _helpers.tpl**

Replace `packages/helm/kopia/templates/_helpers.tpl` with:

```
{{/*
Common labels.
*/}}
{{- define "kopia.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: kopia
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Per-repository resource name. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.repoFullname" -}}
{{- printf "%s-%s" .root.Release.Name .repo.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Per-repository selector labels. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.repoSelectorLabels" -}}
app.kubernetes.io/name: kopia
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .repo.name }}
{{- end }}

{{/*
Fail rendering when a source references an unknown repository or omits retention.
*/}}
{{- define "kopia.validateSources" -}}
{{- $repoNames := list }}
{{- range .Values.repositories }}{{- $repoNames = append $repoNames .name }}{{- end }}
{{- range .Values.sources }}
{{- if not (has .repository $repoNames) }}
{{- fail (printf "source %q references unknown repository %q" .name .repository) }}
{{- end }}
{{- if not .retention }}
{{- fail (printf "source %q must set retention (explicit retention is required)" .name) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Backend-specific env vars. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.backendEnv" -}}
{{- $b := .repo.backend }}
{{- if eq $b.type "gcs" }}
- name: REPO_TYPE
  value: gcs
- name: GCS_BUCKET
  value: {{ $b.gcs.bucket | quote }}
- name: GCS_CREDENTIALS_FILE
  value: /credentials/gcs/credentials.json
{{- else if eq $b.type "s3" }}
- name: REPO_TYPE
  value: s3
- name: S3_BUCKET
  value: {{ $b.s3.bucket | quote }}
- name: S3_ENDPOINT
  value: {{ $b.s3.endpoint | quote }}
{{- with $b.s3.region }}
- name: S3_REGION
  value: {{ . | quote }}
{{- end }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ $b.s3.credentialsSecret }}
      key: access_key_id
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $b.s3.credentialsSecret }}
      key: secret_access_key
{{- else }}
{{- fail (printf "repository %q: unsupported backend type %q" .repo.name $b.type) }}
{{- end }}
{{- end }}

{{/*
Env shared by bootstrap initContainer, server, and verify CronJob.
Context: dict "root" $ "repo" <entry>, optional "usernameOverride" <string>.
*/}}
{{- define "kopia.repoEnv" -}}
- name: TZ
  value: {{ .root.Values.timezone | quote }}
- name: KOPIA_CONFIG_PATH
  value: /app/config/repository.config
- name: KOPIA_LOG_DIR
  value: /tmp/kopia-logs
- name: KOPIA_CACHE_SIZE_MB
  value: {{ .repo.cacheSizeMB | default 5000 | quote }}
- name: KOPIA_OVERRIDE_USERNAME
  value: {{ .usernameOverride | default .repo.identity.username | quote }}
- name: KOPIA_OVERRIDE_HOSTNAME
  value: {{ .repo.identity.hostname | quote }}
- name: KOPIA_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .repo.passwordSecret.name }}
      key: {{ .repo.passwordSecret.key | default "password" }}
{{- include "kopia.backendEnv" . }}
{{- end }}

{{/*
Volume mounts shared by bootstrap initContainer, server, and verify CronJob.
Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.repoStateMounts" -}}
- name: state
  mountPath: /app
- name: scripts
  mountPath: /app/scripts
  readOnly: true
- name: tmp
  mountPath: /tmp
{{- if eq .repo.backend.type "gcs" }}
- name: gcs-credentials
  mountPath: /credentials/gcs
  readOnly: true
{{- end }}
{{- end }}

{{/*
Backend credential volumes. Context: dict "root" $ "repo" <repositories entry>.
*/}}
{{- define "kopia.backendVolumes" -}}
{{- if eq .repo.backend.type "gcs" }}
- name: gcs-credentials
  secret:
    secretName: {{ .repo.backend.gcs.credentialsSecret }}
    items:
      - key: sa_json
        path: credentials.json
{{- end }}
{{- end }}
```

- [ ] **Step 5: Write the validation template**

Create `packages/helm/kopia/templates/validation.yaml`:

```
{{- include "kopia.validateSources" . -}}
```

- [ ] **Step 6: Write the fixtures**

Create `packages/helm/kopia/tests/fixtures/single-gcs.yaml` (mirrors the eventual production overlay):

```yaml
repositories:
  - name: primary
    backend:
      type: gcs
      gcs:
        bucket: test-bucket
        credentialsSecret: gcp-credentials
    identity:
      username: root
      hostname: kopia
    passwordSecret:
      name: backup
      key: password

sources:
  - name: documents
    repository: primary
    mountPath: /Volumes/Documents
    nfsPath: /var/nfs/shared/Documents
    schedule: "15 4 * * *"
    retention:
      latest: 3
      daily: 14
      weekly: 8
      monthly: 12
      annual: 2
    chronos: true
```

Create `packages/helm/kopia/tests/fixtures/multi-backend.yaml` (two repositories — GCS and S3 — with sources mapped individually):

```yaml
repositories:
  - name: primary
    backend:
      type: gcs
      gcs:
        bucket: gcs-bucket-a
        credentialsSecret: gcp-credentials
    identity:
      username: root
      hostname: kopia
    passwordSecret:
      name: backup
      key: password
  - name: media
    backend:
      type: s3
      s3:
        bucket: s3-bucket-b
        endpoint: s3.us-east-1.amazonaws.com
        region: us-east-1
        credentialsSecret: aws-credentials
    identity:
      username: kopia
      hostname: media
    passwordSecret:
      name: backup-media
      key: password

sources:
  - name: documents
    repository: primary
    mountPath: /Volumes/Documents
    nfsPath: /var/nfs/shared/Documents
    schedule: "15 4 * * *"
    retention:
      latest: 3
      daily: 14
      weekly: 8
      monthly: 12
      annual: 2
    chronos: true
  - name: scans
    repository: primary
    mountPath: /data/scans
    nfsPath: /var/nfs/shared/Scans
    schedule: "45 4 * * *"
    retention:
      latest: 3
      daily: 30
      weekly: 8
      monthly: 6
    chronos: true
  - name: media
    repository: media
    mountPath: /data/media
    nfsPath: /var/nfs/shared/Media
    schedule: "0 5 * * 0"
    retention:
      latest: 2
      weekly: 4
      monthly: 6
    chronos: false
```

Create `packages/helm/kopia/tests/fixtures/bad-repo-ref.yaml`:

```yaml
repositories:
  - name: primary
    backend:
      type: gcs
      gcs:
        bucket: test-bucket
        credentialsSecret: gcp-credentials
    identity:
      username: root
      hostname: kopia
    passwordSecret:
      name: backup
      key: password

sources:
  - name: documents
    repository: nonexistent
    mountPath: /Volumes/Documents
    nfsPath: /var/nfs/shared/Documents
    schedule: "15 4 * * *"
    retention:
      latest: 3
    chronos: false
```

- [ ] **Step 7: Write the render test harness**

Create `packages/helm/kopia/tests/render-test.sh`:

```bash
#!/usr/bin/env bash
# Render tests for the kopia chart: helm-template each fixture, run
# grep-based assertions, then validate with kubeconform when available.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

assert_contains() { # file substring description
  if ! grep -qF -- "$2" "$1"; then
    echo "FAIL: $3 (missing: $2)"
    fail=1
  fi
}

assert_not_contains() { # file substring description
  if grep -qF -- "$2" "$1"; then
    echo "FAIL: $3 (forbidden: $2)"
    fail=1
  fi
}

assert_count() { # file regex expected description
  local n
  n=$(grep -cE -- "$2" "$1" || true)
  if [[ "$n" -ne "$3" ]]; then
    echo "FAIL: $4 (expected $3 matches of '$2', got $n)"
    fail=1
  fi
}

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

helm template backup . --namespace backup \
  -f tests/fixtures/single-gcs.yaml > "$out/single.yaml"
helm template backup . --namespace backup \
  -f tests/fixtures/multi-backend.yaml > "$out/multi.yaml"

if helm template backup . --namespace backup \
    -f tests/fixtures/bad-repo-ref.yaml > /dev/null 2>&1; then
  echo "FAIL: expected render failure for unknown repository reference"
  fail=1
fi

# ---- assertions ----
# ---- end assertions ----

if command -v kubeconform > /dev/null 2>&1; then
  for f in "$out/single.yaml" "$out/multi.yaml"; do
    kubeconform -strict -ignore-missing-schemas \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
      < "$f"
  done
fi

if [[ "$fail" -ne 0 ]]; then
  echo "render tests FAILED"
  exit 1
fi
echo "render tests OK"
```

```bash
chmod +x packages/helm/kopia/tests/render-test.sh
```

- [ ] **Step 8: Run the harness**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: `render tests OK` (fixtures render — validation passes, no resource templates exist yet so output is empty; the bad-repo-ref fixture must fail to render).

Run: `shellcheck -S error packages/helm/kopia/tests/render-test.sh`
Expected: exit 0, no output.

- [ ] **Step 9: Commit**

```bash
git add packages/helm/kopia
git commit -m "feat(kopia): v2 chart interface - repositories[] x sources[] with validation and render tests"
```

---

### Task 3: Per-source NFS PVs/PVCs and per-repository config PVCs

**Files:**
- Create: `packages/helm/kopia/templates/pv.yaml`
- Create: `packages/helm/kopia/templates/pvc.yaml`
- Modify: `packages/helm/kopia/tests/render-test.sh` (add assertions)

**Interfaces:**
- Consumes: helpers `kopia.labels` from Task 2.
- Produces: PV `<namespace>-src-<source>` (ReadOnlyMany, storageClass `nfs`, Retain); PVC `src-<source>` bound to it; PVC `config-<repoName>` (ReadWriteMany, storageClass `nfs-csi`). Task 7's Deployment and Task 8's CronJob reference claim names `src-<source>` and `config-<repoName>`.

- [ ] **Step 1: Add failing assertions**

Insert into `tests/render-test.sh` between the assertion markers:

```bash
# Task 3: per-source PVs/PVCs + per-repo config PVCs
assert_contains "$out/single.yaml" "name: backup-src-documents" "namespaced source PV name (avoids legacy backup-documents PV collision)"
assert_contains "$out/single.yaml" "path: /var/nfs/shared/Documents" "source PV nfs path"
assert_contains "$out/single.yaml" "volumeName: backup-src-documents" "source PVC pinned to its PV"
assert_contains "$out/single.yaml" "name: config-primary" "per-repository config PVC"
assert_contains "$out/single.yaml" "storageClassName: nfs-csi" "config PVC uses dynamic nfs-csi"
assert_count "$out/multi.yaml" "^kind: PersistentVolume$" 3 "one PV per source"
assert_count "$out/multi.yaml" "^kind: PersistentVolumeClaim$" 5 "3 source PVCs + 2 config PVCs"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: FAIL lines for each new assertion, exit 1.

- [ ] **Step 3: Write pv.yaml**

Create `packages/helm/kopia/templates/pv.yaml`:

```yaml
{{- range $src := .Values.sources }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  # Namespaced prefix: PVs are cluster-scoped and the legacy chart owns backup-<name>.
  name: {{ $.Release.Namespace }}-src-{{ $src.name }}
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
spec:
  accessModes:
    - ReadOnlyMany
  capacity:
    storage: {{ $src.capacity | default $.Values.nfs.defaultCapacity }}
  mountOptions:
    - hard
    - ro
  nfs:
    server: {{ $.Values.nfs.server }}
    path: {{ $src.nfsPath }}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs
  volumeMode: Filesystem
{{- end }}
```

- [ ] **Step 4: Write pvc.yaml**

Create `packages/helm/kopia/templates/pvc.yaml`:

```yaml
{{- range $repo := .Values.repositories }}
---
# Kopia config + cache for the {{ $repo.name }} server (survives restarts)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: config-{{ $repo.name }}
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $repo.name }}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: {{ $repo.configSize | default "20Gi" }}
  storageClassName: nfs-csi
{{- end }}
{{- range $src := .Values.sources }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: src-{{ $src.name }}
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
spec:
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: {{ $src.capacity | default $.Values.nfs.defaultCapacity }}
  storageClassName: nfs
  volumeName: {{ $.Release.Namespace }}-src-{{ $src.name }}
{{- end }}
```

- [ ] **Step 5: Run tests, verify they pass**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: `render tests OK`.

- [ ] **Step 6: Commit**

```bash
git add packages/helm/kopia
git commit -m "feat(kopia): per-source NFS PV/PVC pairs and per-repository config PVCs"
```

---

### Task 4: Bootstrap/verify scripts and per-repository scripts ConfigMap

Static shell scripts (shellcheck-able files, no Helm templating inside the scripts) driven by env vars and a rendered `sources.conf` data file. This fixes spec R1 (connect-first, `set -euo pipefail`), R3 (explicit retention), R4 (pinned maintenance ownership), R5 (unconditional idempotent `kopia policy set`).

**Files:**
- Create: `packages/helm/kopia/files/repo-connect.sh`
- Create: `packages/helm/kopia/files/bootstrap.sh`
- Create: `packages/helm/kopia/files/verify.sh`
- Create: `packages/helm/kopia/templates/configmap-scripts.yaml`
- Modify: `packages/helm/kopia/tests/render-test.sh` (add assertions)

**Interfaces:**
- Consumes: helpers from Task 2; env contract from `kopia.repoEnv`/`kopia.backendEnv` (`REPO_TYPE`, `GCS_BUCKET`, `GCS_CREDENTIALS_FILE`, `S3_BUCKET`, `S3_ENDPOINT`, `S3_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `KOPIA_OVERRIDE_USERNAME`, `KOPIA_OVERRIDE_HOSTNAME`, `KOPIA_CACHE_SIZE_MB`, `KOPIA_PASSWORD`).
- Produces: ConfigMap `<release>-<repoName>-scripts` with keys `repo-connect.sh`, `bootstrap.sh`, `verify.sh`, `sources.conf`. `sources.conf` line format (pipe-separated): `mountPath|schedule|latest|hourly|daily|weekly|monthly|annual|chronos`. Shell functions `repo_connect` (connect only) and `repo_connect_or_create`. `verify.sh` additionally reads `VERIFY_FILES_PERCENT`, `VERIFY_FILE_PARALLELISM`, optional `CHRONOS_TOKEN`/`CHRONOS_PING_BASE`. Task 7 mounts this ConfigMap at `/app/scripts` and runs `/app/scripts/bootstrap.sh`; Task 8 runs `/app/scripts/verify.sh`.

- [ ] **Step 1: Add failing assertions**

Insert into `tests/render-test.sh` assertions section:

```bash
# Task 4: scripts configmap + sources.conf
assert_contains "$out/single.yaml" "name: backup-primary-scripts" "per-repo scripts configmap"
assert_contains "$out/single.yaml" "/Volumes/Documents|15 4 * * *|3|0|14|8|12|2|true" "documents sources.conf line (explicit retention)"
assert_contains "$out/single.yaml" "repo_connect_or_create" "bootstrap uses connect-first"
assert_contains "$out/single.yaml" "kopia maintenance set" "maintenance ownership pinned"
assert_contains "$out/multi.yaml" "/data/media|0 5 * * 0|2|0|0|4|6|0|false" "media sources.conf line (omitted retention -> 0)"
assert_count "$out/multi.yaml" "^  sources.conf: " 2 "one sources.conf per repository"
assert_count "$out/multi.yaml" "/data/media\|0 5" 1 "media source appears only in its own repository's conf"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: FAIL lines for Task 4 assertions, exit 1.

- [ ] **Step 3: Write files/repo-connect.sh**

```bash
#!/usr/bin/env bash
# Shared connect logic for bootstrap.sh and verify.sh (sourced, not executed).
# Requires env: REPO_TYPE, KOPIA_PASSWORD, KOPIA_OVERRIDE_USERNAME,
# KOPIA_OVERRIDE_HOSTNAME, KOPIA_CACHE_SIZE_MB, plus backend vars
# (GCS_BUCKET + GCS_CREDENTIALS_FILE, or S3_BUCKET + S3_ENDPOINT + AWS creds).

repo_args() {
  case "$REPO_TYPE" in
    gcs)
      backend_args=(gcs --bucket="$GCS_BUCKET" --credentials-file="$GCS_CREDENTIALS_FILE")
      ;;
    s3)
      backend_args=(s3 --bucket="$S3_BUCKET" --endpoint="$S3_ENDPOINT"
        --access-key="$AWS_ACCESS_KEY_ID" --secret-access-key="$AWS_SECRET_ACCESS_KEY")
      if [[ -n "${S3_REGION:-}" ]]; then
        backend_args+=(--region="$S3_REGION")
      fi
      ;;
    *)
      echo "[ERROR] unsupported REPO_TYPE: ${REPO_TYPE}" >&2
      return 1
      ;;
  esac
  common_args=(
    --override-username="$KOPIA_OVERRIDE_USERNAME"
    --override-hostname="$KOPIA_OVERRIDE_HOSTNAME"
    --cache-directory=/app/cache
    --content-cache-size-mb="$KOPIA_CACHE_SIZE_MB"
    --metadata-cache-size-mb="$KOPIA_CACHE_SIZE_MB"
  )
}

repo_connect() {
  repo_args
  kopia repository connect "${backend_args[@]}" "${common_args[@]}"
}

repo_connect_or_create() {
  repo_args
  kopia repository connect "${backend_args[@]}" "${common_args[@]}" \
    || kopia repository create "${backend_args[@]}" "${common_args[@]}"
}
```

- [ ] **Step 4: Write files/bootstrap.sh**

```bash
#!/usr/bin/env bash
# Idempotent repository bootstrap (initContainer): connect-or-create the
# repository, apply per-source policies from sources.conf, pin maintenance
# ownership to the server identity.
set -euo pipefail

# shellcheck source=files/repo-connect.sh
source /app/scripts/repo-connect.sh

mkdir -p /app/config /app/cache

repo_connect_or_create
kopia repository status

while IFS='|' read -r path schedule latest hourly daily weekly monthly annual chronos; do
  [[ -z "$path" ]] && continue
  echo "[INFO] applying policy for ${path}"
  policy_args=(
    --compression=zstd-better-compression
    --snapshot-time-crontab="$schedule"
    --keep-latest="$latest"
    --keep-hourly="$hourly"
    --keep-daily="$daily"
    --keep-weekly="$weekly"
    --keep-monthly="$monthly"
    --keep-annual="$annual"
  )
  if [[ "$chronos" == "true" ]]; then
    policy_args+=(
      --before-snapshot-root-action=/app/actions/chronos-start.sh
      --after-snapshot-root-action=/app/actions/chronos-success.sh
      --action-command-mode=optional
    )
  fi
  kopia policy set "$path" "${policy_args[@]}"
done < /app/scripts/sources.conf

echo "[INFO] pinning maintenance ownership to ${KOPIA_OVERRIDE_USERNAME}@${KOPIA_OVERRIDE_HOSTNAME}"
kopia maintenance set \
  --owner="${KOPIA_OVERRIDE_USERNAME}@${KOPIA_OVERRIDE_HOSTNAME}" \
  --enable-quick=true \
  --enable-full=true
```

- [ ] **Step 5: Write files/verify.sh**

```bash
#!/usr/bin/env bash
# Periodic snapshot verification (CronJob): connect as a distinct identity
# (never the maintenance owner) and sample file content to catch corruption
# before a restore is ever needed. Pings Chronos on success when configured.
set -euo pipefail

# shellcheck source=files/repo-connect.sh
source /app/scripts/repo-connect.sh

mkdir -p /app/config /app/cache

repo_connect
kopia snapshot verify \
  --verify-files-percent="${VERIFY_FILES_PERCENT}" \
  --file-parallelism="${VERIFY_FILE_PARALLELISM}"

if [[ -n "${CHRONOS_TOKEN:-}" ]]; then
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${CHRONOS_TOKEN}" > /dev/null || true
fi
echo "[INFO] verification complete"
```

- [ ] **Step 6: Write templates/configmap-scripts.yaml**

```yaml
{{- range $repo := .Values.repositories }}
{{- $ctx := dict "root" $ "repo" $repo }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "kopia.repoFullname" $ctx }}-scripts
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $repo.name }}
data:
  repo-connect.sh: |
{{ $.Files.Get "files/repo-connect.sh" | indent 4 }}
  bootstrap.sh: |
{{ $.Files.Get "files/bootstrap.sh" | indent 4 }}
  verify.sh: |
{{ $.Files.Get "files/verify.sh" | indent 4 }}
  sources.conf: |
    {{- range $src := $.Values.sources }}
    {{- if eq $src.repository $repo.name }}
    {{- $r := $src.retention }}
    {{ $src.mountPath }}|{{ $src.schedule }}|{{ $r.latest | default 0 }}|{{ $r.hourly | default 0 }}|{{ $r.daily | default 0 }}|{{ $r.weekly | default 0 }}|{{ $r.monthly | default 0 }}|{{ $r.annual | default 0 }}|{{ $src.chronos | default false }}
    {{- end }}
    {{- end }}
{{- end }}
```

- [ ] **Step 7: Run tests and shellcheck, verify pass**

Run:
```bash
bash packages/helm/kopia/tests/render-test.sh
shellcheck -S error packages/helm/kopia/files/*.sh packages/helm/kopia/tests/render-test.sh
```
Expected: `render tests OK`; shellcheck exits 0.

- [ ] **Step 8: Commit**

```bash
git add packages/helm/kopia
git commit -m "feat(kopia): idempotent bootstrap/verify scripts with per-repo sources.conf"
```

---

### Task 5: Per-source Chronos action hooks

One Chronos token per source (spec §3.5). Kopia exposes `KOPIA_SOURCE_PATH` to root actions; the hook resolves source path → source name via a rendered `sources.map`, then reads the token from the mounted `chronos` secret (one key per source name).

**Files:**
- Create: `packages/helm/kopia/files/chronos-start.sh`
- Create: `packages/helm/kopia/files/chronos-success.sh`
- Create: `packages/helm/kopia/templates/configmap-actions.yaml`
- Modify: `packages/helm/kopia/tests/render-test.sh` (add assertions)

**Interfaces:**
- Consumes: `kopia.labels`. Source list from values.
- Produces: ConfigMap `<release>-actions` (keys `chronos-start.sh`, `chronos-success.sh`, `sources.map`; map line format `mountPath|sourceName`). Task 7 mounts it at `/app/actions` (0755) and the `chronos` secret at `/app/chronos`; Task 4's policies already point at `/app/actions/chronos-*.sh`.

- [ ] **Step 1: Add failing assertions**

```bash
# Task 5: chronos actions + sources.map
assert_contains "$out/single.yaml" "name: backup-actions" "shared actions configmap"
assert_contains "$out/single.yaml" "/Volumes/Documents|documents" "sources.map entry"
assert_contains "$out/single.yaml" "/app/chronos/" "token resolved from mounted secret dir"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: FAIL lines for Task 5 assertions, exit 1.

- [ ] **Step 3: Write files/chronos-start.sh**

```bash
#!/usr/bin/env bash
# Chronos "start" ping (before-snapshot-root action). Resolves the per-source
# token via sources.map. Best-effort: never blocks or fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
name=$(awk -F'|' -v p="${KOPIA_SOURCE_PATH:-}" '$1 == p {print $2}' /app/actions/sources.map 2> /dev/null)
if [ -n "$name" ] && [ -f "/app/chronos/${name}" ]; then
  token=$(cat "/app/chronos/${name}")
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${token}/start?rid=${KOPIA_SNAPSHOT_ID:-}" > /dev/null 2>&1
fi
exit 0
```

- [ ] **Step 4: Write files/chronos-success.sh**

```bash
#!/usr/bin/env bash
# Chronos "success" ping (after-snapshot-root action; runs only on success).
# Resolves the per-source token via sources.map. Best-effort: never fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
name=$(awk -F'|' -v p="${KOPIA_SOURCE_PATH:-}" '$1 == p {print $2}' /app/actions/sources.map 2> /dev/null)
if [ -n "$name" ] && [ -f "/app/chronos/${name}" ]; then
  token=$(cat "/app/chronos/${name}")
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${token}?rid=${KOPIA_SNAPSHOT_ID:-}" > /dev/null 2>&1
fi
exit 0
```

- [ ] **Step 5: Write templates/configmap-actions.yaml**

```yaml
{{- if .Values.chronos.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-actions
  labels:
    {{- include "kopia.labels" . | nindent 4 }}
data:
  chronos-start.sh: |
{{ .Files.Get "files/chronos-start.sh" | indent 4 }}
  chronos-success.sh: |
{{ .Files.Get "files/chronos-success.sh" | indent 4 }}
  sources.map: |
    {{- range .Values.sources }}
    {{ .mountPath }}|{{ .name }}
    {{- end }}
{{- end }}
```

- [ ] **Step 6: Run tests and shellcheck, verify pass**

Run:
```bash
bash packages/helm/kopia/tests/render-test.sh
shellcheck -S error packages/helm/kopia/files/*.sh
```
Expected: `render tests OK`; shellcheck exits 0.

- [ ] **Step 7: Commit**

```bash
git add packages/helm/kopia
git commit -m "feat(kopia): per-source chronos tokens via sources.map lookup"
```

---

### Task 6: Selfsigned ClusterIssuer (platform) + per-repository server Certificate

The platform only has Let's Encrypt issuers, which can't issue for `*.svc.cluster.local`. Add a `selfsigned` ClusterIssuer to `k8s/platform/cert-manager` and a per-repository Certificate template. Clients never verify this cert (kubelet tcpSocket probes; UI via port-forward with a browser warning), so self-signed is sufficient.

**Files:**
- Create: `k8s/platform/cert-manager/selfsigned.yaml`
- Modify: `k8s/platform/cert-manager/kustomization.yaml` (add to `resources:`)
- Create: `packages/helm/kopia/templates/certificate.yaml`
- Modify: `packages/helm/kopia/tests/render-test.sh` (add assertions)

**Interfaces:**
- Consumes: `kopia.repoFullname`, `kopia.labels`; `tls.issuerRef` values (default `{name: selfsigned, kind: ClusterIssuer}`).
- Produces: ClusterIssuer `selfsigned` (cluster-wide, usable by future internal services); Certificate + TLS Secret named `<release>-<repoName>-tls`. Task 7 mounts that secret at `/tls`.

- [ ] **Step 1: Add failing assertions**

```bash
# Task 6: per-repository server certificate
assert_contains "$out/single.yaml" "kind: Certificate" "cert-manager certificate rendered"
assert_contains "$out/single.yaml" "secretName: backup-primary-tls" "tls secret name consumed by deployment"
assert_contains "$out/single.yaml" "backup-primary.backup.svc.cluster.local" "service FQDN SAN"
assert_count "$out/multi.yaml" "^kind: Certificate$" 2 "one certificate per repository"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: FAIL lines for Task 6 assertions, exit 1.

- [ ] **Step 3: Write the platform ClusterIssuer**

Create `k8s/platform/cert-manager/selfsigned.yaml`:

```yaml
---
# Self-signed issuer for internal (*.svc.cluster.local) certificates that
# public ACME issuers cannot sign. First consumer: kopia server TLS.
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
```

Add `- selfsigned.yaml` to the `resources:` list in `k8s/platform/cert-manager/kustomization.yaml` (alongside `letsencrypt-prod.yaml` / `letsencrypt-staging.yaml`).

- [ ] **Step 4: Write templates/certificate.yaml**

```yaml
{{- range $repo := .Values.repositories }}
{{- $ctx := dict "root" $ "repo" $repo }}
{{- $name := include "kopia.repoFullname" $ctx }}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $name }}-tls
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $repo.name }}
spec:
  secretName: {{ $name }}-tls
  issuerRef:
    {{- toYaml $.Values.tls.issuerRef | nindent 4 }}
  dnsNames:
    - {{ $name }}.{{ $.Release.Namespace }}.svc.cluster.local
    - {{ $name }}.{{ $.Release.Namespace }}.svc
{{- end }}
```

- [ ] **Step 5: Run tests and platform build, verify pass**

Run:
```bash
bash packages/helm/kopia/tests/render-test.sh
kustomize build --enable-helm k8s/platform/cert-manager | kubeconform -strict -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
Expected: `render tests OK`; kubeconform exits 0.

- [ ] **Step 6: Commit**

```bash
git add packages/helm/kopia k8s/platform/cert-manager
git commit -m "feat(kopia): per-repo server TLS via new selfsigned ClusterIssuer"
```

---

### Task 7: Hardened server Deployment + Service (per repository)

The core of the refactor: one Deployment per repository running an authenticated TLS `kopia server` (fixes S1), exact-key env injection (fixes S2), full pod hardening (fixes S3), bootstrap initContainer, tcpSocket probes (fixes R6; tcpSocket because Kopia's basic-auth 401 fails httpGet), sources of that repository mounted read-only.

**Files:**
- Create: `packages/helm/kopia/templates/deployment.yaml`
- Create: `packages/helm/kopia/templates/service.yaml`
- Modify: `packages/helm/kopia/tests/render-test.sh` (add assertions)

**Interfaces:**
- Consumes: helpers from Task 2; PVCs `config-<repo>` / `src-<source>` (Task 3); ConfigMaps `<release>-<repo>-scripts` (Task 4) and `<release>-actions` (Task 5); TLS secret `<release>-<repo>-tls` (Task 6); secrets `kopia-server` (keys `password`, `control-password`) and `chronos` (per-source keys) provided by the overlay (Task 10).
- Produces: Deployment + Service `<release>-<repoName>`, HTTPS on port `.Values.server.port` (51515). The UI is ClusterIP-only, reached via `kubectl port-forward`.

- [ ] **Step 1: Add failing assertions**

```bash
# Task 7: hardened server deployment + service
assert_count "$out/single.yaml" "^kind: Deployment$" 1 "single repo -> single deployment"
assert_count "$out/multi.yaml" "^kind: Deployment$" 2 "one server deployment per repository"
assert_count "$out/multi.yaml" "^kind: Service$" 2 "one service per repository"
assert_not_contains "$out/single.yaml" "allow-extremely-dangerous-unauthenticated-server-on-the-network" "dangerous flag removed"
assert_not_contains "$out/single.yaml" "--insecure" "insecure flag removed"
assert_not_contains "$out/single.yaml" "--without-password" "without-password flag removed"
assert_not_contains "$out/single.yaml" "envFrom" "no wholesale secret env dump"
assert_contains "$out/single.yaml" "--tls-cert-file=/tls/tls.crt" "server TLS enabled"
assert_contains "$out/single.yaml" "containerPort: 51515" "kopia default HTTPS port"
assert_contains "$out/single.yaml" "runAsNonRoot: true" "non-root pod"
assert_contains "$out/single.yaml" "readOnlyRootFilesystem: true" "read-only root fs"
assert_contains "$out/single.yaml" "KOPIA_SERVER_CONTROL_PASSWORD" "control API password from secret"
assert_contains "$out/single.yaml" "tcpSocket" "tcp probes (kopia basic-auth 401 breaks httpGet)"
assert_contains "$out/single.yaml" 'value: "root"' "legacy identity override preserved"
assert_contains "$out/single.yaml" "mountPath: /Volumes/Documents" "legacy source mount path preserved"
assert_count "$out/multi.yaml" "mountPath: /data/media$" 1 "media source mounted only on its own repo server"
assert_contains "$out/multi.yaml" "name: AWS_SECRET_ACCESS_KEY" "s3 credentials via env secretKeyRef"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: FAIL lines for Task 7 assertions, exit 1.

- [ ] **Step 3: Write templates/deployment.yaml**

```yaml
{{- range $repo := .Values.repositories }}
{{- $ctx := dict "root" $ "repo" $repo }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "kopia.repoFullname" $ctx }}
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $repo.name }}
spec:
  replicas: 1
  revisionHistoryLimit: 3
  strategy:
    type: Recreate
  selector:
    matchLabels:
      {{- include "kopia.repoSelectorLabels" $ctx | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "kopia.repoSelectorLabels" $ctx | nindent 8 }}
    spec:
      securityContext:
        {{- toYaml $.Values.podSecurityContext | nindent 8 }}
      initContainers:
        - name: bootstrap
          image: {{ $.Values.image.repository }}:{{ $.Values.image.tag }}
          imagePullPolicy: {{ $.Values.image.pullPolicy }}
          securityContext:
            {{- toYaml $.Values.containerSecurityContext | nindent 12 }}
          command: ["/bin/bash", "/app/scripts/bootstrap.sh"]
          env:
            {{- include "kopia.repoEnv" $ctx | nindent 12 }}
          volumeMounts:
            {{- include "kopia.repoStateMounts" $ctx | nindent 12 }}
      containers:
        - name: server
          image: {{ $.Values.image.repository }}:{{ $.Values.image.tag }}
          imagePullPolicy: {{ $.Values.image.pullPolicy }}
          securityContext:
            {{- toYaml $.Values.containerSecurityContext | nindent 12 }}
          command:
            - /bin/bash
            - -c
            - |-
              exec kopia server start \
                --address=0.0.0.0:{{ $.Values.server.port }} \
                --tls-cert-file=/tls/tls.crt \
                --tls-key-file=/tls/tls.key \
                --server-username={{ $.Values.server.uiUsername }} \
                --server-control-username={{ $.Values.server.controlUsername }} \
                --enable-actions
          ports:
            - name: https
              containerPort: {{ $.Values.server.port }}
              protocol: TCP
          readinessProbe:
            tcpSocket:
              port: https
            initialDelaySeconds: 15
            periodSeconds: 15
          livenessProbe:
            tcpSocket:
              port: https
            initialDelaySeconds: 120
            periodSeconds: 60
          resources:
            {{- toYaml $.Values.resources | nindent 12 }}
          env:
            {{- include "kopia.repoEnv" $ctx | nindent 12 }}
            - name: KOPIA_SERVER_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ $.Values.secrets.server.name }}
                  key: password
            - name: KOPIA_SERVER_CONTROL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ $.Values.secrets.server.name }}
                  key: control-password
            {{- if $.Values.chronos.enabled }}
            - name: CHRONOS_PING_BASE
              value: {{ $.Values.chronos.pingBase | quote }}
            {{- end }}
          volumeMounts:
            {{- include "kopia.repoStateMounts" $ctx | nindent 12 }}
            - name: tls
              mountPath: /tls
              readOnly: true
            {{- if $.Values.chronos.enabled }}
            - name: actions
              mountPath: /app/actions
              readOnly: true
            - name: chronos
              mountPath: /app/chronos
              readOnly: true
            {{- end }}
            {{- range $src := $.Values.sources }}
            {{- if eq $src.repository $repo.name }}
            - name: src-{{ $src.name }}
              mountPath: {{ $src.mountPath }}
              readOnly: true
            {{- end }}
            {{- end }}
      volumes:
        - name: state
          persistentVolumeClaim:
            claimName: config-{{ $repo.name }}
        - name: tmp
          emptyDir: {}
        - name: scripts
          configMap:
            name: {{ include "kopia.repoFullname" $ctx }}-scripts
            defaultMode: 0755
        - name: tls
          secret:
            secretName: {{ include "kopia.repoFullname" $ctx }}-tls
        {{- if $.Values.chronos.enabled }}
        - name: actions
          configMap:
            name: {{ $.Release.Name }}-actions
            defaultMode: 0755
        - name: chronos
          secret:
            secretName: {{ $.Values.secrets.chronos.name }}
        {{- end }}
        {{- include "kopia.backendVolumes" $ctx | nindent 8 }}
        {{- range $src := $.Values.sources }}
        {{- if eq $src.repository $repo.name }}
        - name: src-{{ $src.name }}
          persistentVolumeClaim:
            claimName: src-{{ $src.name }}
        {{- end }}
        {{- end }}
{{- end }}
```

- [ ] **Step 4: Write templates/service.yaml**

```yaml
{{- range $repo := .Values.repositories }}
{{- $ctx := dict "root" $ "repo" $repo }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "kopia.repoFullname" $ctx }}
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $repo.name }}
spec:
  selector:
    {{- include "kopia.repoSelectorLabels" $ctx | nindent 4 }}
  ports:
    - name: https
      protocol: TCP
      port: {{ $.Values.server.port }}
      targetPort: {{ $.Values.server.port }}
{{- end }}
```

- [ ] **Step 5: Run tests, verify they pass**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: `render tests OK`.

- [ ] **Step 6: Commit**

```bash
git add packages/helm/kopia
git commit -m "feat(kopia): hardened TLS+auth server deployment per repository"
```

---

### Task 8: Snapshot verification CronJob (per repository)

Fixes R7. Runs `verify.sh` (Task 4) monthly as identity `verify@<repo-hostname>` (never the maintenance owner), with its own emptyDir state so it can't disturb the server's config/cache PVC. Pod labels use component `<repo>-verify` so the Service selector never matches verify pods.

**Files:**
- Create: `packages/helm/kopia/templates/cronjob-verify.yaml`
- Modify: `packages/helm/kopia/tests/render-test.sh` (add assertions)

**Interfaces:**
- Consumes: `kopia.repoEnv` with `"usernameOverride" "verify"`; scripts ConfigMap (Task 4); `verify.*` and `chronos.*` values; chronos secret key `verify-<repoName>` (optional).
- Produces: CronJob `<release>-<repoName>-verify`.

- [ ] **Step 1: Add failing assertions**

```bash
# Task 8: verify cronjob
assert_contains "$out/single.yaml" "name: backup-primary-verify" "verify cronjob per repository"
assert_contains "$out/single.yaml" "schedule: \"30 6 1 * *\"" "monthly off-peak schedule"
assert_contains "$out/single.yaml" "key: verify-primary" "per-repo verify chronos token key"
assert_contains "$out/single.yaml" 'value: "verify"' "distinct verify identity (not maintenance owner)"
assert_count "$out/multi.yaml" "^kind: CronJob$" 2 "one verify job per repository"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: FAIL lines for Task 8 assertions, exit 1.

- [ ] **Step 3: Write templates/cronjob-verify.yaml**

```yaml
{{- if .Values.verify.enabled }}
{{- range $repo := .Values.repositories }}
{{- $ctx := dict "root" $ "repo" $repo "usernameOverride" "verify" }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "kopia.repoFullname" $ctx }}-verify
  labels:
    {{- include "kopia.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $repo.name }}-verify
spec:
  schedule: {{ $.Values.verify.schedule | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        metadata:
          labels:
            app.kubernetes.io/name: kopia
            app.kubernetes.io/instance: {{ $.Release.Name }}
            app.kubernetes.io/component: {{ $repo.name }}-verify
        spec:
          restartPolicy: Never
          securityContext:
            {{- toYaml $.Values.podSecurityContext | nindent 12 }}
          containers:
            - name: verify
              image: {{ $.Values.image.repository }}:{{ $.Values.image.tag }}
              imagePullPolicy: {{ $.Values.image.pullPolicy }}
              securityContext:
                {{- toYaml $.Values.containerSecurityContext | nindent 16 }}
              command: ["/bin/bash", "/app/scripts/verify.sh"]
              env:
                {{- include "kopia.repoEnv" $ctx | nindent 16 }}
                - name: VERIFY_FILES_PERCENT
                  value: {{ $.Values.verify.filesPercent | quote }}
                - name: VERIFY_FILE_PARALLELISM
                  value: {{ $.Values.verify.fileParallelism | quote }}
                {{- if $.Values.chronos.enabled }}
                - name: CHRONOS_PING_BASE
                  value: {{ $.Values.chronos.pingBase | quote }}
                - name: CHRONOS_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: {{ $.Values.secrets.chronos.name }}
                      key: verify-{{ $repo.name }}
                      optional: true
                {{- end }}
              resources:
                {{- toYaml $.Values.resources | nindent 16 }}
              volumeMounts:
                {{- include "kopia.repoStateMounts" $ctx | nindent 16 }}
          volumes:
            - name: state
              emptyDir: {}
            - name: tmp
              emptyDir: {}
            - name: scripts
              configMap:
                name: {{ include "kopia.repoFullname" $ctx }}-scripts
                defaultMode: 0755
            {{- include "kopia.backendVolumes" $ctx | nindent 12 }}
{{- end }}
{{- end }}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `bash packages/helm/kopia/tests/render-test.sh`
Expected: `render tests OK`.

- [ ] **Step 5: Commit**

```bash
git add packages/helm/kopia
git commit -m "feat(kopia): monthly snapshot verify cronjob per repository"
```

---

### Task 9: Rewrite the chart README

**Files:**
- Modify: `packages/helm/kopia/README.md` (full replace)

**Interfaces:**
- Consumes: the final chart interface (Tasks 2–8). Documentation only.

- [ ] **Step 1: Replace README.md**

```markdown
# kopia Helm Chart (v2)

Multi-source, multi-repository Kopia backup. Each entry in `repositories[]`
renders one hardened Kopia server (TLS + basic auth, Deployment/Service/
Certificate/config PVC/verify CronJob) against one storage bucket. Each entry
in `sources[]` maps an NFS share to a repository by name and gets its own
ReadOnlyMany PV/PVC, cron schedule, explicit retention, and Chronos token.
Snapshot scheduling runs inside the Kopia server (policy crontabs owned by
the server's stable `user@host` identity) — the only k8s CronJob is the
monthly `kopia snapshot verify`.

## Adding a source

Append to `sources[]` in the app overlay values (and add a matching key to
the `chronos` secret / 1Password item). No new deployment is created unless
you also add a repository.

## Adding a repository (separate bucket / backend)

Append to `repositories[]` with `backend.type: gcs` or `s3`, its own
`identity` and `passwordSecret`; point sources at it via `repository:`.

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` / `image.tag` | `kopia/kopia` / `0.23.1` | Pinned image |
| `timezone` | `America/Chicago` | TZ for server + jobs |
| `repositories[].name` | — | Repository name; suffixes all per-repo resources |
| `repositories[].backend.type` | — | `gcs` or `s3` |
| `repositories[].backend.gcs.bucket` | — | GCS bucket |
| `repositories[].backend.gcs.credentialsSecret` | — | Secret with key `sa_json` |
| `repositories[].backend.s3.{bucket,endpoint,region}` | — | S3-compatible target (`region` optional) |
| `repositories[].backend.s3.credentialsSecret` | — | Secret with keys `access_key_id`, `secret_access_key` |
| `repositories[].identity.{username,hostname}` | — | Stable `user@host`; owns all sources + maintenance |
| `repositories[].passwordSecret.{name,key}` | key: `password` | Repository password secret |
| `repositories[].cacheSizeMB` | `5000` | Content + metadata cache size |
| `repositories[].configSize` | `20Gi` | nfs-csi PVC for kopia config + cache |
| `sources[].name` | — | Source name; PVC `src-<name>`, chronos secret key `<name>` |
| `sources[].repository` | — | Name of the owning repository (validated at render) |
| `sources[].mountPath` | — | In-pod path; also the kopia source path (lineage!) |
| `sources[].nfsPath` | — | NFS export path |
| `sources[].schedule` | — | `--snapshot-time-crontab` for the source policy |
| `sources[].retention.{latest,hourly,daily,weekly,monthly,annual}` | required; omitted field = 0 | Explicit retention |
| `sources[].chronos` | `false` | Attach chronos before/after root actions |
| `sources[].capacity` | `nfs.defaultCapacity` | PV/PVC size |
| `server.port` | `51515` | HTTPS port |
| `server.uiUsername` / `server.controlUsername` | `kopia` / `server-control` | Basic-auth + control API users |
| `nfs.server` | `192.168.10.5` | NFS server address |
| `nfs.defaultCapacity` | `1Ti` | Default source PV capacity |
| `tls.issuerRef` | `selfsigned` ClusterIssuer | cert-manager issuer for server certs |
| `verify.{enabled,schedule,filesPercent,fileParallelism}` | `true`, `30 6 1 * *`, `1`, `4` | Monthly snapshot verification |
| `chronos.{enabled,pingBase}` | `true`, chronos.bruner.family | Health-check pings |
| `secrets.server.name` | `kopia-server` | Keys `password`, `control-password` |
| `secrets.chronos.name` | `chronos` | One key per source name + `verify-<repository>` |
| `podSecurityContext` / `containerSecurityContext` | non-root 65532, RO rootfs, no caps | Pod hardening (tune `runAsUser` to NFS export perms) |
| `resources` | 100m/256Mi – 1/1Gi | Server + verify job resources |

## External secret dependencies (provided by the app overlay)

All are `OnePasswordItem`-materialized Secrets in the app namespace:
`kopia-server` (UI/control credentials), per-repository password secrets,
per-backend credential secrets (`gcp-credentials` key `sa_json`, or an S3
secret with `access_key_id`/`secret_access_key`), and `chronos` (per-source
token keys). The chart creates none of them.

## UI access

ClusterIP only. `kubectl -n backup port-forward svc/backup-primary 51515:51515`
then https://localhost:51515 (self-signed cert; log in with `server.uiUsername`
and the `kopia-server` secret's `password`).

## Tests

`bash tests/render-test.sh` — helm-template renders of `tests/fixtures/*`
with grep assertions + kubeconform.
```

- [ ] **Step 2: Verify docs lint**

Run: `yamllint . && bash packages/helm/kopia/tests/render-test.sh`
Expected: no yamllint errors (warnings acceptable); `render tests OK`.

- [ ] **Step 3: Commit**

```bash
git add packages/helm/kopia/README.md
git commit -m "docs(kopia): document v2 repositories/sources chart interface"
```

---

### Task 10: New `k8s/apps/backup/` app overlay

Spec Phase 2: the new ArgoCD-discovered app, `sources: [documents]` against the existing bucket with legacy identity `root@kopia` and legacy mount path — snapshot lineage continues untouched. All four secrets become OnePasswordItems (fixes S4).

**Files:**
- Create: `k8s/apps/backup/namespace.yaml`
- Create: `k8s/apps/backup/secrets.yaml`
- Create: `k8s/apps/backup/kopia-values.yaml`
- Create: `k8s/apps/backup/kustomization.yaml`

**Interfaces:**
- Consumes: chart `packages/helm/kopia` v2 (Tasks 2–9); ApplicationSet `apps` auto-discovers the directory — no ArgoCD wiring needed.
- Produces: namespace `backup`; Secrets `backup`, `kopia-server`, `chronos`, `gcp-credentials` (via 1Password operator); release `backup` → Deployment/Service `backup-primary`, PV `backup-src-documents`.

- [ ] **Step 1: Write namespace.yaml**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: backup
```

- [ ] **Step 2: Write secrets.yaml**

```yaml
---
# Repository password (same item the legacy deployment uses — same repo)
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: backup
spec:
  itemPath: "vaults/lab/items/UNAS Backup Password"
---
# Kopia server UI + control API credentials (keys: password, control-password)
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: kopia-server
spec:
  itemPath: "vaults/lab/items/Kopia Server"
---
# Chronos ping tokens — one key per source name + verify-<repository>
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: chronos
spec:
  itemPath: "vaults/lab/items/Chronos Backup"
---
# GCS service account (key: sa_json) — was a manually created secret (spec S4)
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: gcp-credentials
spec:
  itemPath: "vaults/lab/items/GCP Backup Service Account"
```

- [ ] **Step 3: Write kopia-values.yaml**

```yaml
repositories:
  - name: primary
    backend:
      type: gcs
      gcs:
        bucket: backup-unas-vol-documents-9851   # existing repo, history preserved in place
        credentialsSecret: gcp-credentials
    identity:
      username: root    # legacy identity — keeps snapshot lineage (spec §6.1)
      hostname: kopia
    passwordSecret:
      name: backup
      key: password

sources:
  - name: documents
    repository: primary
    mountPath: /Volumes/Documents   # legacy path — keeps snapshot lineage
    nfsPath: /var/nfs/shared/Documents
    schedule: "15 4 * * *"
    retention:
      latest: 3
      daily: 14
      weekly: 8
      monthly: 12
      annual: 2
    chronos: true
```

- [ ] **Step 4: Write kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: backup
helmGlobals:
  chartHome: ../../../packages/helm
helmCharts:
  - name: kopia
    releaseName: backup
    namespace: backup
    valuesFile: kopia-values.yaml
resources:
  - namespace.yaml
  - secrets.yaml
```

- [ ] **Step 5: Validate the full repo the way CI does**

Run:
```bash
kustomize build --enable-helm k8s/apps/backup > /tmp/backup-app.yaml
grep -c 'kind: Deployment' /tmp/backup-app.yaml                       # expected: 1
grep 'backup-unas-vol-documents-9851' /tmp/backup-app.yaml | head -1  # expected: bucket present
grep -c 'kind: OnePasswordItem' /tmp/backup-app.yaml                  # expected: 4
kubeconform -strict -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  < /tmp/backup-app.yaml
for d in bootstrap/argocd bootstrap/root k8s/platform/*/ k8s/apps/*/; do
  kustomize build --enable-helm "$d" > /dev/null && echo "OK $d"
done
yamllint .
```
Expected: all greps match, kubeconform exits 0, every directory prints `OK`, yamllint reports no errors.

- [ ] **Step 6: Commit**

```bash
git add k8s/apps/backup
git commit -m "feat(backup): new single-server multi-source kopia app against existing bucket"
```

---

### Task 11: Cutover runbook + CLAUDE.md update

The cutover itself (spec Phase 3) is manual by decision — this task writes the runbook and updates repo docs so the transition state is discoverable.

**Files:**
- Create: `docs/kopia-cutover-runbook.md`
- Modify: `CLAUDE.md` (apps list + local helm charts section)

**Interfaces:**
- Consumes: everything above. Documentation only.

- [ ] **Step 1: Write docs/kopia-cutover-runbook.md**

```markdown
# Kopia Cutover Runbook — backup-documents → backup

Manual steps for spec Phase 2 prep, Phase 3 cutover, and Phase 4 expansion.
The new app is `k8s/apps/backup/` (chart `packages/helm/kopia` v2); the old
one is `k8s/apps/backup-documents/` (frozen chart `packages/helm/kopia-legacy`).

## Phase 2 prep — BEFORE merging the branch

1. In Chronos, create ping monitors: one per source (`documents`) and one for
   verification (`verify-primary`, monthly cadence matching `30 6 1 * *`).
2. In 1Password vault `lab`, create:
   - `Kopia Server` — fields `password`, `control-password` (generate both).
   - `Chronos Backup` — field `documents` (existing documents token or a new
     one) and field `verify-primary` (verify token).
   - `GCP Backup Service Account` — field `sa_json` with the JSON currently in
     the manually created `gcp-credentials` secret:
     `kubectl -n backup-documents get secret gcp-credentials -o jsonpath='{.data.sa_json}' | base64 -d`

## Phase 3 — cutover

1. Scale the old server to 0 (avoid duplicate snapshots/pings; two clients on
   one repo is safe, duplicate schedules are not):
   `kubectl -n backup-documents scale deploy/backup --replicas=0`
2. Merge the branch. ArgoCD creates the `backup` app.
3. Watch: `kubectl -n backup get pods -w` — `bootstrap` initContainer must
   connect (NOT create) the repository, then the server goes Ready.
   If bootstrap fails reading NFS or writing /app as uid 65532, adjust
   `podSecurityContext` in `k8s/apps/backup/kopia-values.yaml` to match the
   UNAS export permissions (last resort: runAsUser 0 + runAsNonRoot false —
   revisit export squash settings instead).
4. Verify lineage and schedule:
   - `kubectl -n backup exec deploy/backup-primary -c server -- kopia snapshot list --all`
     → historical `root@kopia:/Volumes/Documents` snapshots present.
   - `kubectl -n backup exec deploy/backup-primary -c server -- kopia maintenance info`
     → owner `root@kopia`, quick+full enabled.
   - Next 04:15 snapshot fires; Chronos `documents` monitor pings start+success.
   - Run the verify job once: `kubectl -n backup create job --from=cronjob/backup-primary-verify verify-manual`
5. UI check: `kubectl -n backup port-forward svc/backup-primary 51515:51515`,
   log in with `kopia` / `Kopia Server`.`password`.

## Phase 3 — cleanup (after ≥1 successful scheduled snapshot)

1. Delete the old app and frozen chart on a branch, merge; ArgoCD prunes the
   `backup-documents` namespace:
   `trash k8s/apps/backup-documents packages/helm/kopia-legacy`
2. Retire the old Chronos monitor and the old `Chronos Backup Documents`
   1Password item if unused.
3. Delete the released legacy PV after the namespace is pruned (Retain policy):
   `kubectl delete pv backup-documents`

## Phase 4 — expansion (per new share)

1. Chronos monitor + new field on the `Chronos Backup` 1Password item
   (field name = source name).
2. Append a `sources:` entry in `k8s/apps/backup/kopia-values.yaml`
   (`mountPath: /data/<name>`, staggered `schedule`, explicit `retention`).
3. A new bucket/backend instead? Append a `repositories:` entry (own
   `identity`, `passwordSecret`, backend credentials secret in
   `secrets.yaml`) and point the source's `repository:` at it.
4. Push; ArgoCD syncs. Verify the new policy:
   `kubectl -n backup exec deploy/backup-primary -c server -- kopia policy list`

## Storage-side hardening (follow-up, outside this repo)

Enable GCS object versioning / soft-delete on the bucket and scope the
service account to `roles/storage.objectAdmin` on this bucket only
(Terraform GCP workflow).
```

- [ ] **Step 2: Update CLAUDE.md**

In the **Apps** list, replace the `backup-documents` line:

```markdown
- **`backup/`** — Kopia backup server: single hardened server per repository, multi-source (uses `packages/helm/kopia`)
- **`backup-documents/`** — Legacy Kopia deployment (frozen `packages/helm/kopia-legacy`; delete after cutover — see `docs/kopia-cutover-runbook.md`)
```

In **Local Helm Charts**, replace the `kopia/` bullet:

```markdown
- **`kopia/`** — Multi-source/multi-repository Kopia backup chart. `repositories[]` (one TLS+auth server per bucket, GCS or S3) × `sources[]` (per-source NFS PV, schedule, retention, Chronos token), all in one `kopia-values.yaml`.
- **`kopia-legacy/`** — Frozen pre-refactor chart; only `k8s/apps/backup-documents` uses it (deleted at cutover).
```

- [ ] **Step 3: Verify and commit**

Run: `yamllint . && bash packages/helm/kopia/tests/render-test.sh`
Expected: no yamllint errors; `render tests OK`.

```bash
git add docs/kopia-cutover-runbook.md CLAUDE.md
git commit -m "docs: kopia cutover runbook and repo doc updates"
```

---

## Runtime verification notes (post-merge, human — not CI-checkable)

- `KOPIA_SERVER_PASSWORD` / `KOPIA_SERVER_CONTROL_PASSWORD` env vars are Kopia's documented kingpin envar equivalents of `--server-password` / `--server-control-password`; confirm auth works at cutover step 5 before deleting the old app.
- `runAsUser: 65532` must be able to read the UNAS NFS exports and write the nfs-csi config PVC — runbook Phase 3 step 3 covers the fallback.
```
