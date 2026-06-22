# Kopia → Chronos Job Health Checks via Kopia Actions

**Date:** 2026-06-21
**Status:** Approved design

## Problem

The cluster runs two Kopia backups (`backup-documents`, `backup-photos`), each a
single `kopia server` Deployment that snapshots an NFS-mounted PV to a GCS bucket.
Snapshots are fired by the Kopia server's **internal scheduler** via the policy
`--snapshot-time-crontab="15 4 * * *"` (America/Chicago), set in the init container.
There is currently no signal to the Chronos job health-check system
(`https://chronos.bruner.family`) when these backups run, succeed, or silently stop.

## Goal

Report each backup's lifecycle to Chronos so a failed or missed backup raises an alert,
using **Kopia Actions** as the only hook into the server-scheduled snapshot lifecycle.

## Approach

Use two root-level Kopia Actions per backup, mapping the snapshot lifecycle onto
Chronos Path A (token-based) pings:

- `before-snapshot-root-action` → Chronos `start`
- `after-snapshot-root-action` → Chronos `success` (this hook runs **only on success**)

Failure detection is **dead-man only**: Kopia has no on-error action hook, and because
snapshots are fired by the server's internal scheduler there is nothing external to wrap
to catch a non-zero exit. A failed or missed backup is therefore detected by Chronos when
the expected `success` ping does not arrive within the job's configured grace period.

### Data flow

```
Kopia server scheduler fires snapshot
        │
        ├─ before-snapshot-root-action  →  curl /ping/$TOKEN/start?rid=$KOPIA_SNAPSHOT_ID
        │
        ├─ (snapshot runs)
        │
        └─ after-snapshot-root-action   →  curl /ping/$TOKEN?rid=$KOPIA_SNAPSHOT_ID   (success only)

Snapshot fails / never runs → no success ping → Chronos grace period expires → alert
```

- **`rid` = `KOPIA_SNAPSHOT_ID`.** Kopia passes the same `KOPIA_SNAPSHOT_ID` to both the
  before- and after-action of a given snapshot, so start↔success linking and Chronos
  duration computation work without any state shared between the two scripts.
- Actions are enabled with `--enable-actions` on `kopia server start`.
- The policy sets `--action-command-mode=optional` so a Chronos outage can never block or
  fail an actual backup. The scripts also `exit 0` unconditionally as a second guard.

## Components & file changes

### Base — `k8s/bases/kopia/` (shared, identical for both backups)

1. **`actions/chronos-start.sh`** and **`actions/chronos-success.sh`** — bash + curl
   scripts (see below). `curl` is present at `/usr/bin/curl` in the `kopia/kopia` image;
   bash is at `/usr/bin/bash`.
2. **`kustomization.yaml`** — add a `configMapGenerator` named `kopia-actions` containing
   the two scripts.
3. **`deployment.yaml`**:
   - Add `--enable-actions` to the `kopia server start` command in the main container.
   - In the init container, apply the action flags to the policy **idempotently on every
     start** — not only inside the existing create-if-missing block. Existing policies
     already skip the create branch, so the action flags must be set unconditionally:
     ```bash
     kopia policy set "$BACKUP_TARGET" \
       --before-snapshot-root-action /app/actions/chronos-start.sh \
       --after-snapshot-root-action  /app/actions/chronos-success.sh \
       --action-command-mode=optional
     ```
     The init container only stores the script *path* in the policy; it does not need the
     scripts mounted. The main/server container is where the scripts must exist at that
     path at snapshot time.
   - Append a `CHRONOS_TOKEN` env var to the main container, sourced from a secret named
     `chronos`, key `token`:
     ```yaml
     - name: CHRONOS_TOKEN
       valueFrom:
         secretKeyRef:
           name: chronos
           key: token
     ```

### Each overlay — `k8s/namespaces/backup-documents/`, `k8s/namespaces/backup-photos/`

1. **`resources/chronos.yaml`** — a `OnePasswordItem` named `chronos` with its own
   `itemPath` (distinct ping token per Chronos job), added to the overlay's
   `kustomization.yaml` `resources` list. Follows the existing `password.yaml` /
   `OnePasswordItem` pattern.
2. **`patches/deployment.yaml`** — append the `kopia-actions` ConfigMap volume and a
   read-only `volumeMount` at `/app/actions` (mount mode `0755`) to the volume and
   volumeMount lists the overlay already defines. The action scripts are mounted into the
   main container only.

Scripts live in the base because they are byte-identical for both backups; only the token
differs, and the token is injected via the per-overlay `chronos` secret.

## The action scripts

`chronos-start.sh` (before-snapshot-root):

```bash
#!/usr/bin/env bash
# Chronos "start" ping. Best-effort: never blocks or fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
[ -n "$CHRONOS_TOKEN" ] && \
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${CHRONOS_TOKEN}/start?rid=${KOPIA_SNAPSHOT_ID}" >/dev/null 2>&1
exit 0
```

`chronos-success.sh` (after-snapshot-root) is identical except the ping URL omits
`/start`:

```bash
#!/usr/bin/env bash
# Chronos "success" ping. Best-effort: never blocks or fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
[ -n "$CHRONOS_TOKEN" ] && \
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${CHRONOS_TOKEN}?rid=${KOPIA_SNAPSHOT_ID}" >/dev/null 2>&1
exit 0
```

`CHRONOS_PING_BASE` is defaulted in-script and overridable by env. Kopia executes the
scripts via their shebang (`/usr/bin/bash`).

## Error handling

- **Chronos unreachable / slow:** `curl -m 10` bounds the wait; `||`-guarded and
  `exit 0` plus `--action-command-mode=optional` ensure the snapshot proceeds regardless.
- **Missing token:** the `[ -n "$CHRONOS_TOKEN" ]` guard skips the ping silently rather
  than erroring.
- **Snapshot failure:** after-action does not run → no success ping → Chronos grace alert.
- **Pod/server down at scheduled time:** no start and no success → Chronos grace alert.

## Manual setup (Path A, one-time)

1. In the Chronos UI create two jobs (documents, photos). For each, set an **expected
   schedule** matching `15 4 * * *` America/Chicago and a **grace period** long enough to
   cover the longest expected backup runtime. The schedule + grace are what make dead-man
   detection fire.
2. Copy each job's ping token into 1Password and point that overlay's `chronos`
   `OnePasswordItem.itemPath` at it.
3. Document these steps in `k8s/bases/kopia/README.md`.

## Testing

- `kustomize build k8s/namespaces/backup-documents` and `.../backup-photos` render
  cleanly with the new ConfigMap, secret env, volume, and mounts.
- **Live positive check:** `kubectl exec` into a pod and run
  `kopia snapshot create "$BACKUP_TARGET"`; confirm a `start` then `success` ping land in
  Chronos with a computed duration (proves `KOPIA_SNAPSHOT_ID`-as-`rid` linking).
- **Negative check:** confirm that skipping a scheduled run trips the Chronos grace alert.

## Out of scope / non-goals

- No explicit `/fail` ping (no Kopia error hook for server-scheduled snapshots; dead-man
  detection covers failures by design).
- No move away from the Kopia internal scheduler to a Kubernetes CronJob wrapper.
- No change to the GCS repository, encryption, or backup policy schedule itself.

## Decisions made during design

- Action scripts shared in the base (identical for both backups); token injected via env.
- `CHRONOS_PING_BASE` defaulted in-script with env override.
- `--action-command-mode=optional` plus unconditional `exit 0` so Chronos never affects
  backup outcomes.
- Failure handling is dead-man via Chronos (explicitly chosen over a CronJob wrapper).
- Chronos jobs are pre-created in the UI (Path A); pods stay auth-free with one token each.
