# Spec: Kopia Backup Refactor — Single Secure Server, Multiple Scheduled Sources

Status: **Proposed** · Branch: `claude/kopia-backup-refactor-dd045i`

## Goal

Refactor the Kopia deployment from one-server-per-backup-target to a **single
Kopia server** that mounts multiple NFS shares and runs **per-source cron
scheduled snapshots**, aligned with the best practices maintained by the Kopia
project (kopia.io): TLS + authenticated server, explicit retention policies,
pinned maintenance ownership, and periodic snapshot verification.

---

## 1. Review of the Current Implementation

Current shape: `packages/helm/kopia` chart + `k8s/apps/backup-documents`
overlay. One target = one namespace = one GCS bucket = one full Kopia server
Deployment.

### 1.1 Security findings

| # | Finding | Where | Severity |
|---|---------|-------|----------|
| S1 | Server runs `--insecure --without-password --allow-extremely-dangerous-unauthenticated-server-on-the-network` bound to `0.0.0.0:8080`, with a ClusterIP Service. Any pod in the cluster gets full unauthenticated access to the repository UI/API — browse, restore, delete snapshots, edit policies. Kopia's repository server explicitly requires TLS and authentication; the flag name itself is the upstream warning. | `templates/deployment.yaml:97` | High |
| S2 | `envFrom: secretRef` dumps every key of the `backup` secret into the environment *and* `KOPIA_PASSWORD` is set again via `secretKeyRef` — duplicated and broader than needed. | `templates/deployment.yaml:119-129` | Low |
| S3 | Pod hardening is minimal: only `allowPrivilegeEscalation: false`. No `runAsNonRoot`, no `readOnlyRootFilesystem`, no `capabilities: drop: [ALL]`, no `seccompProfile`. | `templates/deployment.yaml` | Medium |
| S4 | `gcp-credentials` is a manually created secret, outside the 1Password operator pattern used everywhere else in this repo. | chart README | Low |

### 1.2 Reliability findings

| # | Finding | Where | Severity |
|---|---------|-------|----------|
| R1 | The repo-existence check tests `/app/cache/kopia.repository`, but `repository.config` sets `cacheDirectory: /cache`, which is **not mounted anywhere**. The marker never persists, so `kopia repository create gcs` runs on *every* pod start and fails against the non-empty bucket. The script has no `set -e`, so the failure is silently swallowed — masking real failures too. | `templates/deployment.yaml:33-38`, `configmap-repository.yaml:18` | High |
| R2 | Because `/cache` is on the container's ephemeral overlay FS, the 5 GB metadata/content cache is rebuilt from GCS after every restart (cost + slow), while the 50 Gi `config` NFS PVC sits mostly unused. | same | Medium |
| R3 | No retention policy is set — only compression and schedule. Kopia's implicit defaults (keep-latest 10, hourly 48, daily 7, weekly 4, monthly 24, annual 3) apply without being pinned in git. | `templates/deployment.yaml:46-49` | Medium |
| R4 | Maintenance ownership is never set. Full/quick maintenance runs only if the connected identity happens to match the owner recorded at `repository create` time. Kopia's guidance is to explicitly designate one `user@host` as maintenance owner. | — | Medium |
| R5 | Policy idempotence via `kopia policy list \| grep $BACKUP_TARGET \| wc -l` is fragile (substring matches, breaks on similar paths). `kopia policy set` is already idempotent — the guard is unnecessary. | `templates/deployment.yaml:43-52` | Low |
| R6 | No liveness/readiness probes on the server container. | `templates/deployment.yaml` | Low |
| R7 | Snapshots are never verified (`kopia snapshot verify`) — restore integrity is untested until it's needed. | — | Medium |

### 1.3 Scalability finding

Adding a second share today means a new namespace, a new GCS bucket, a new
repository password lineage, and a second full Kopia server — duplicated
memory/cache footprint and no deduplication across shares. This is exactly
what the single-server refactor removes.

---

## 2. Kopia Best Practices Applied (kopia.io)

Grounding for the design decisions below:

1. **Server security** — a Kopia server on a non-loopback address should run
   with TLS (`--tls-cert-file`/`--tls-key-file`) and authentication
   (`--server-username` + `--server-password`, with the control API guarded by
   `--server-control-username` + `KOPIA_SERVER_CONTROL_PASSWORD`). Sensitive
   values belong in the environment/secret files, never in flags visible in
   process listings.
2. **One repository, many sources** — a repository supports unlimited
   sources/policies. Each source (`user@host:/path`) carries its own policy:
   schedule (`--snapshot-time-crontab`), retention, compression, actions.
   Deduplication then works *across* sources.
3. **Built-in scheduler** — a running `kopia server` automatically executes
   scheduled snapshots for sources owned by its own `user@host`. No external
   CronJobs are needed for snapshots; the cron expressions live in policies.
   This requires a **stable identity** (`--override-username`/
   `--override-hostname`) so policy ownership always matches the server.
4. **Maintenance** — exactly one `user@host` is the maintenance owner; quick
   maintenance runs ~hourly and full maintenance every 24h by default, driven
   by the long-running server. Pin ownership explicitly
   (`kopia maintenance set --owner=user@host`) and leave quick maintenance
   enabled.
5. **Retention should be explicit** — declare keep-latest/daily/weekly/
   monthly/annual per source rather than relying on defaults.
6. **Verify restores** — run `kopia snapshot verify` periodically (sampling
   file content with `--verify-files-percent`) to catch bit-rot or
   inconsistency before a restore is ever needed.
7. **Actions are opt-in and should stay minimal** — `--enable-actions` is
   required server-side; keep hooks to best-effort root-level scripts
   (the existing Chronos pings already follow this).
8. **Ransomware resilience (storage-side)** — pair Kopia with bucket
   versioning / object lock and a least-privilege service account so a
   compromised cluster can't silently destroy history.

---

## 3. Target Architecture

```
k8s/apps/backup/                      # ONE app, namespace: backup
  kustomization.yaml                  # local kopia chart + resources
  kopia-values.yaml                   # server config + sources[] list
  namespace.yaml
  secrets.yaml                        # OnePasswordItems (repo pw, server creds, chronos, gcp sa)

packages/helm/kopia/                  # refactored chart
  templates/
    deployment.yaml                   # single server, TLS + auth, probes, hardened
    configmap-bootstrap.yaml          # idempotent bootstrap script (initContainer)
    configmap-actions.yaml            # chronos hooks (per-source token lookup)
    pv.yaml / pvc.yaml                # one RO PV/PVC PER SOURCE (ranged) + one cache/config PVC
    service.yaml                      # ClusterIP :51515 (HTTPS)
    certificate.yaml                  # cert-manager Certificate for server TLS
    password.yaml                     # OnePasswordItems
```

### 3.1 Single server, multiple sources

One Deployment (`replicas: 1`, `strategy: Recreate`) runs
`kopia server start`. Each entry in a new `sources:` values list produces:

- a static NFS **PV/PVC pair** (`ReadOnlyMany`, RO mount) at
  `/data/<name>` inside the pod,
- a **policy** applied at bootstrap: schedule, retention, compression,
  Chronos actions.

```yaml
# kopia-values.yaml (overlay) — target shape
server:
  username: kopia            # stable identity: kopia@backup
  hostname: backup

repository:
  gcsBucket: backup-unas-vol-documents-9851   # single repo for all sources

sources:
  - name: documents
    mountPath: /Volumes/Documents   # keep legacy path → preserves snapshot lineage
    nfsPath: /var/nfs/shared/Documents
    schedule: "15 4 * * *"
    retention: {latest: 3, daily: 14, weekly: 8, monthly: 12, annual: 2}
    chronos: true
  - name: scans
    mountPath: /data/scans
    nfsPath: /var/nfs/shared/Scans
    schedule: "45 4 * * *"
    retention: {latest: 3, daily: 30, weekly: 8, monthly: 6}
    chronos: true
```

Scheduling is delegated to Kopia's built-in scheduler (best practice #3):
the server owns all sources (same `user@host`), so `--snapshot-time-crontab`
policies fire in-process. **No k8s CronJobs for snapshots.** Stagger the
crontabs so large sources don't overlap.

> **Identity note / migration constraint:** existing snapshots are owned by
> `root@kopia:/Volumes/Documents`. To preserve lineage the server must keep
> the same `user@host` (or the migration must run
> `kopia snapshot move-history`). See §5.

### 3.2 Server security

- **TLS**: cert-manager `Certificate` (internal issuer already in
  `k8s/platform/cert-manager`) issues a cert for
  `backup.backup.svc.cluster.local`; mounted and passed via
  `--tls-cert-file`/`--tls-key-file`. Serve on Kopia's default port
  `51515`.
- **Auth**: `--server-username` / `--server-password` for the UI/API and
  `--server-control-username` / `KOPIA_SERVER_CONTROL_PASSWORD` for the
  control API — both from a new 1Password item (`kopia-server`). The
  dangerous flags (`--insecure`, `--without-password`,
  `--allow-extremely-dangerous-…`) are removed entirely.
- **Access**: ClusterIP service only; UI reached via
  `kubectl port-forward` (HTTPRoute can be added later through the standard
  gateway flow if wanted — not in scope).
- **Env hygiene**: drop `envFrom`; inject exactly `KOPIA_PASSWORD`,
  `KOPIA_SERVER_CONTROL_PASSWORD`, and the server password via
  `secretKeyRef`.
- **Pod hardening**: `runAsNonRoot` with fixed `runAsUser`/`fsGroup`
  (uid chosen to read the NFS exports), `readOnlyRootFilesystem: true`
  (+ `emptyDir` for `/tmp`), `capabilities: {drop: [ALL]}`,
  `seccompProfile: RuntimeDefault`, on both containers.
- **Secrets**: `gcp-credentials` becomes a `OnePasswordItem` like every
  other secret in the repo (fixes S4).

### 3.3 Reliable bootstrap (initContainer)

Replace the inline heredoc with a ConfigMap-mounted script, `set -euo
pipefail`, and idempotent primitives instead of grep-guards:

```bash
# connect-first: create only if connect fails (fixes R1)
kopia repository connect gcs --bucket "$BUCKET" --credentials-file "$CREDS" \
  || kopia repository create gcs --bucket "$BUCKET" --credentials-file "$CREDS"

# per source — kopia policy set is idempotent, run unconditionally (fixes R5)
kopia policy set "$SRC" \
  --compression=zstd-better-compression \
  --snapshot-time-crontab="$SCHEDULE" \
  --keep-latest=... --keep-daily=... --keep-weekly=... --keep-monthly=... --keep-annual=... \
  --before-snapshot-root-action=/app/actions/chronos-start.sh \
  --after-snapshot-root-action=/app/actions/chronos-success.sh \
  --action-command-mode=optional

# pin maintenance ownership to the server identity (fixes R4)
kopia maintenance set --owner="$KOPIA_USER@$KOPIA_HOST" --enable-quick=true --enable-full=true
```

Cache and config move onto the existing `nfs-csi` PVC
(`cacheDirectory: /app/cache`) so cache and repo state survive restarts
(fixes R1/R2). Cache sizes stay in `repository.config`, generated from
values.

### 3.4 Probes

- **readiness/liveness**: `httpGet` on `/` port `51515`, `scheme: HTTPS`
  (kubelet skips cert verification). Generous `initialDelaySeconds` on
  liveness since first connect may download metadata.

### 3.5 Monitoring (Chronos)

Keep the before/after root-action pattern (already best-practice-shaped).
Change: one Chronos token **per source**. The `chronos` secret gains one key
per source name; the hook scripts resolve the token from the mounted secret
dir using the source path Kopia exposes to actions
(`KOPIA_SOURCE_PATH → token file`). A failed/missed backup surfaces as a
missed ping in Chronos (start without success), unchanged.

### 3.6 Verification CronJob (fixes R7)

One k8s `CronJob` (monthly, off-peak) in the chart:

```
kopia snapshot verify --verify-files-percent=1 --file-parallelism=4
```

It connects with the same repo secret/credentials (read-only workload) and
pings its own Chronos token. This is the only k8s CronJob in the design —
snapshot scheduling stays inside Kopia.

### 3.7 Repository layout decision

**Recommendation: one repository (one GCS bucket) for all sources**, reusing
the existing `backup-unas-vol-documents-9851` bucket so Documents history is
preserved in place.

- Pros: cross-source dedup, one password, one maintenance cycle, one thing
  to verify and monitor.
- Cons: single blast radius (mitigate with bucket versioning below); bucket
  name no longer matches its contents (cosmetic).
- Alternative (rejected): repo-per-share keeps blast radii separate but
  reintroduces per-repo maintenance/verification/secrets and forfeits dedup —
  the main cost the refactor removes.

**Storage-side hardening (best practice #8, follow-up outside this repo):**
enable GCS object versioning (or a soft-delete/retention policy) on the
bucket and scope the service account to `roles/storage.objectAdmin` on this
bucket only.

---

## 4. Chart Interface Changes (summary)

| Old value | New value |
|---|---|
| `target.{name,sourcePath,nfsPath,schedule,description}` (single) | `sources[]` list: `{name, mountPath, nfsPath, schedule, retention{...}, chronos}` |
| `storage.gcsBucket` | `repository.gcsBucket` (+ `repository.cacheSizeMB`) |
| — | `server.{username,hostname}` (stable identity) |
| — | `secrets.server.name` (UI + control credentials) |
| — | `tls.certificateSecretName` / issuer ref |
| — | `verify.{enabled,schedule,filesPercent}` |
| `chronos.pingBase`, `chronos.enabled` | unchanged; token becomes per-source key |

`kubeconform` + `kustomize build --enable-helm` in CI cover the rendered
output as today.

---

## 5. Migration Plan (phased, ArgoCD-driven)

**Phase 1 — chart refactor.** Implement §3 in `packages/helm/kopia`
(multi-source templates, secure server, bootstrap script, probes, hardening,
verify CronJob). Validate with `kustomize build --enable-helm` + kubeconform.

**Phase 2 — new app.** Add `k8s/apps/backup/` with `sources: [documents]`
pointing at the **existing** bucket. Pre-create the new 1Password item
(`kopia-server`) and the per-source Chronos tokens.

**Phase 3 — cutover.**
1. Merge; ArgoCD creates the `backup` namespace app. Two servers briefly
   coexist against one repo — safe (Kopia handles concurrent clients), but
   scale the old Deployment to 0 first to avoid duplicate snapshots/pings.
2. Identity check: if keeping `root@kopia`, set `server.username: root`,
   `server.hostname: kopia` and lineage continues untouched. If moving to
   `kopia@backup`, run once:
   `kopia snapshot move-history root@kopia:/Volumes/Documents kopia@backup:/Volumes/Documents`
   and re-pin maintenance ownership.
3. Verify: pod healthy, `kopia snapshot list` shows historical Documents
   snapshots, next scheduled snapshot fires, Chronos pings arrive.
4. Delete `k8s/apps/backup-documents/` — ArgoCD prunes the old namespace.

**Phase 4 — expand.** Add remaining shares (`scans`, others from the UNAS
layout) as `sources[]` entries + NFS PVs + Chronos tokens. Each addition is
now a values-list edit, not a new deployment.

---

## 6. Open Decisions

1. **Server identity**: keep `root@kopia` (zero-touch lineage) vs rename to
   `kopia@backup` with a one-time `snapshot move-history`. Spec default:
   keep `root@kopia` — least migration risk.
2. **UI exposure**: port-forward only (spec default) vs HTTPRoute +
   certificate through the shared gateway.
3. **Cache placement**: NFS `nfs-csi` PVC (spec default; survives restarts,
   slower) vs node-local `emptyDir` with `sizeLimit` (fast, rebuilt each
   restart, costs GCS reads).
4. **GCS versioning/object lock**: recommended follow-up in the GCP/Terraform
   side, not blocked on this refactor.
