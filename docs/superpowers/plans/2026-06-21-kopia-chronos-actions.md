# Kopia → Chronos Health Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Report each Kopia backup's snapshot lifecycle to the Chronos job health-check system via Kopia Actions, so failed or missed backups raise dead-man alerts.

**Architecture:** Two root-level Kopia Actions (`before-snapshot-root-action`, `after-snapshot-root-action`) call small bash+curl scripts that ping Chronos `start` / `success`. The scripts and their ConfigMap live in the shared base (`k8s/bases/kopia`); each overlay supplies a distinct ping token via a `OnePasswordItem`. Failure is detected by Chronos when an expected `success` ping never arrives. No change to the Kopia internal scheduler or GCS repository.

**Tech Stack:** Kubernetes, Kustomize (base + overlays), Kopia (`kopia/kopia` image), Chronos health checks (Path A token pings), 1Password operator (`OnePasswordItem`).

## Global Constraints

- LF line endings only; never CRLF.
- Use `trash`, not `rm`, when deleting files.
- Bootstrap installs operators only — all app resources live under `k8s/namespaces/`. This change touches only `k8s/bases/kopia/` and the two backup overlays; nothing in `k8s/bootstrap/`.
- `rid` (Chronos run id) MUST be `KOPIA_SNAPSHOT_ID` — the value Kopia passes identically to the before- and after-action of one snapshot.
- Chronos ping base URL: `https://chronos.bruner.family/ping` (defaulted in-script, env-overridable via `CHRONOS_PING_BASE`).
- Action scripts MUST be best-effort: `curl -fsS -m 10`, guarded, and `exit 0` unconditionally; policy uses `--action-command-mode=optional`. A Chronos outage must never block or fail a backup.
- Scripts are byte-identical for both backups and live ONLY in the base. Only the token differs (per-overlay `chronos` secret, key `token`).
- Verification is via `kustomize build <overlay>` + `grep` (no unit-test framework in this repo); live cluster checks are listed but not runnable from the workstation without cluster access.
- Two overlays must stay in sync: `k8s/namespaces/backup-documents/` and `k8s/namespaces/backup-photos/`.

---

### Task 1: Action scripts + ConfigMap in base

**Files:**
- Create: `k8s/bases/kopia/actions/chronos-start.sh`
- Create: `k8s/bases/kopia/actions/chronos-success.sh`
- Modify: `k8s/bases/kopia/kustomization.yaml`
- Verify: `kustomize build k8s/namespaces/backup-documents`

**Interfaces:**
- Consumes: env `CHRONOS_TOKEN`, `KOPIA_SNAPSHOT_ID` (provided to the script by Kopia and by Task 2's deployment env), optional `CHRONOS_PING_BASE`.
- Produces: a generated ConfigMap whose generator base-name is `kopia-actions`, containing keys `chronos-start.sh` and `chronos-success.sh`. Task 4 mounts this ConfigMap at `/app/actions`. Task 2's policy references the script paths `/app/actions/chronos-start.sh` and `/app/actions/chronos-success.sh`.

- [ ] **Step 1: Verify the marker is absent (baseline)**

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'kopia-actions' || true`
Expected: `0`

- [ ] **Step 2: Create `k8s/bases/kopia/actions/chronos-start.sh`**

```bash
#!/usr/bin/env bash
# Chronos "start" ping (before-snapshot-root action).
# Best-effort: never blocks or fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
[ -n "$CHRONOS_TOKEN" ] && \
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${CHRONOS_TOKEN}/start?rid=${KOPIA_SNAPSHOT_ID}" >/dev/null 2>&1
exit 0
```

- [ ] **Step 3: Create `k8s/bases/kopia/actions/chronos-success.sh`**

```bash
#!/usr/bin/env bash
# Chronos "success" ping (after-snapshot-root action; runs only on success).
# Best-effort: never blocks or fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
[ -n "$CHRONOS_TOKEN" ] && \
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${CHRONOS_TOKEN}?rid=${KOPIA_SNAPSHOT_ID}" >/dev/null 2>&1
exit 0
```

- [ ] **Step 4: Add the `configMapGenerator` to `k8s/bases/kopia/kustomization.yaml`**

The file currently ends after the `resources:` list. Append this block at the end:

```yaml
configMapGenerator:
  - name: kopia-actions
    files:
      - actions/chronos-start.sh
      - actions/chronos-success.sh
```

Resulting file:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml
- pv.yaml
- pvc.yaml
- password.yaml

configMapGenerator:
  - name: kopia-actions
    files:
      - actions/chronos-start.sh
      - actions/chronos-success.sh
```

- [ ] **Step 5: Verify the ConfigMap renders**

Run: `kustomize build k8s/namespaces/backup-documents | grep -A2 'name: kopia-actions'`
Expected: output shows a `ConfigMap` named `kopia-actions-<hash>` (hash suffix added by the generator).

Also confirm the script content is present:
Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'chronos.bruner.family/ping'`
Expected: `2` (the default base URL appears in both script bodies).

- [ ] **Step 6: Commit**

```bash
git add k8s/bases/kopia/actions/chronos-start.sh k8s/bases/kopia/actions/chronos-success.sh k8s/bases/kopia/kustomization.yaml
git commit -m "feat(kopia): add Chronos ping action scripts to base"
```

---

### Task 2: Wire base deployment — enable actions, policy hooks, token env

**Files:**
- Modify: `k8s/bases/kopia/deployment.yaml`
- Verify: `kustomize build k8s/namespaces/backup-documents`

**Interfaces:**
- Consumes: script paths `/app/actions/chronos-start.sh` and `/app/actions/chronos-success.sh` (Task 1; mounted by Task 4); secret `chronos` key `token` (Task 3).
- Produces: server started with `--enable-actions`; policy carries `--before-snapshot-root-action` / `--after-snapshot-root-action` / `--action-command-mode=optional`; main container exposes `CHRONOS_TOKEN` env to the action scripts (which run as child processes of the server and inherit its environment).

- [ ] **Step 1: Verify markers absent (baseline)**

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'enable-actions\|CHRONOS_TOKEN\|snapshot-root-action' || true`
Expected: `0`

- [ ] **Step 2: Add `--enable-actions` to the server start command**

In `k8s/bases/kopia/deployment.yaml`, find the main container command line:

```
              kopia server start --address=http://0.0.0.0:8080 --insecure --without-password
```

Replace with:

```
              kopia server start --address=http://0.0.0.0:8080 --insecure --without-password --enable-actions
```

- [ ] **Step 3: Add idempotent policy action hooks in the init container**

In the init container script, the policy block currently ends with:

```bash
              else
                echo "[INFO]: Backup target found for '$BACKUP_TARGET'"
              fi
```

Immediately after that closing `fi`, add a separate unconditional block (runs on every start so existing policies also pick up the hooks):

```bash

              if [[ ! -z $BACKUP_TARGET ]]; then
                echo "[INFO]: Ensuring Chronos action hooks on policy for '$BACKUP_TARGET'..."
                kopia policy set "$BACKUP_TARGET" \
                  --before-snapshot-root-action /app/actions/chronos-start.sh \
                  --after-snapshot-root-action /app/actions/chronos-success.sh \
                  --action-command-mode=optional
              fi
```

- [ ] **Step 4: Add the `CHRONOS_TOKEN` env to the main container**

In `k8s/bases/kopia/deployment.yaml`, the main container's `env:` block currently ends with the `KOPIA_PASSWORD` entry:

```yaml
            - name: KOPIA_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: backup
                  key: password
```

Append after it (same indentation):

```yaml
            - name: CHRONOS_TOKEN
              valueFrom:
                secretKeyRef:
                  name: chronos
                  key: token
```

- [ ] **Step 5: Verify all three markers render**

Run: `kustomize build k8s/namespaces/backup-documents | grep -c -- '--enable-actions'`
Expected: `1`

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'before-snapshot-root-action /app/actions/chronos-start.sh'`
Expected: `1`

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'name: CHRONOS_TOKEN'`
Expected: `1`

Run: `kustomize build k8s/namespaces/backup-documents >/dev/null && echo OK`
Expected: `OK` (still builds).

- [ ] **Step 6: Commit**

```bash
git add k8s/bases/kopia/deployment.yaml
git commit -m "feat(kopia): enable actions, set Chronos policy hooks, inject token env"
```

---

### Task 3: Per-overlay Chronos token secret (both overlays)

**Files:**
- Create: `k8s/namespaces/backup-documents/resources/chronos.yaml`
- Create: `k8s/namespaces/backup-photos/resources/chronos.yaml`
- Modify: `k8s/namespaces/backup-documents/kustomization.yaml`
- Modify: `k8s/namespaces/backup-photos/kustomization.yaml`
- Verify: `kustomize build` of both overlays

**Interfaces:**
- Consumes: nothing from prior tasks.
- Produces: a `OnePasswordItem` named `chronos` in each namespace, materializing a K8s secret `chronos` with key `token` (consumed by Task 2's env). Requires two 1Password items in vault `lab`, each with a field named `token` holding that job's Chronos ping token: `Chronos Backup Documents` and `Chronos Backup Photos` (created manually per Task 5).

- [ ] **Step 1: Verify marker absent (baseline)**

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'name: chronos' || true`
Expected: `0`

- [ ] **Step 2: Create `k8s/namespaces/backup-documents/resources/chronos.yaml`**

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: chronos
spec:
  itemPath: "vaults/lab/items/Chronos Backup Documents"
```

- [ ] **Step 3: Create `k8s/namespaces/backup-photos/resources/chronos.yaml`**

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: chronos
spec:
  itemPath: "vaults/lab/items/Chronos Backup Photos"
```

- [ ] **Step 4: Reference the new resource in both kustomizations**

In `k8s/namespaces/backup-documents/kustomization.yaml`, the `resources:` list currently reads:

```yaml
resources:
  - resources/namespace.yaml
  - ../../bases/kopia/
```

Change it to:

```yaml
resources:
  - resources/namespace.yaml
  - resources/chronos.yaml
  - ../../bases/kopia/
```

Apply the identical change to `k8s/namespaces/backup-photos/kustomization.yaml`.

- [ ] **Step 5: Verify the secret source renders in both overlays**

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'kind: OnePasswordItem'`
Expected: `2` (existing `backup` + new `chronos`).

Run: `kustomize build k8s/namespaces/backup-photos | grep -c 'kind: OnePasswordItem'`
Expected: `2`

Run: `kustomize build k8s/namespaces/backup-photos | grep -A4 'name: chronos' | grep -c 'Chronos Backup Photos'`
Expected: `1`

- [ ] **Step 6: Commit**

```bash
git add k8s/namespaces/backup-documents/resources/chronos.yaml k8s/namespaces/backup-photos/resources/chronos.yaml k8s/namespaces/backup-documents/kustomization.yaml k8s/namespaces/backup-photos/kustomization.yaml
git commit -m "feat(kopia): add per-overlay Chronos token OnePasswordItem"
```

---

### Task 4: Mount action scripts into both overlay deployments

**Files:**
- Modify: `k8s/namespaces/backup-documents/patches/deployment.yaml`
- Modify: `k8s/namespaces/backup-photos/patches/deployment.yaml`
- Verify: `kustomize build` of both overlays

**Interfaces:**
- Consumes: ConfigMap base-name `kopia-actions` (Task 1); script path `/app/actions/...` referenced by the policy (Task 2).
- Produces: the `kopia-actions` ConfigMap mounted read-only at `/app/actions` (mode `0755`) in the main container, so Kopia can execute the scripts. Kustomize rewrites the `kopia-actions` volume reference to the hashed generated name automatically.

- [ ] **Step 1: Verify marker absent (baseline)**

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'mountPath: /app/actions' || true`
Expected: `0`

- [ ] **Step 2: Add the `actions` volume in `backup-documents` patch**

In `k8s/namespaces/backup-documents/patches/deployment.yaml`, the volumes patch currently lists `backup`, `config`, `repo-config`, `gcp-credentials` under:

```yaml
- op: add
  path: "/spec/template/spec/volumes"
  value:
    - name: backup
      persistentVolumeClaim:
        claimName: backup
    - name: config
      persistentVolumeClaim:
        claimName: config
    - name: repo-config
      configMap:
        name: repo-config
    - name: gcp-credentials
      secret:
        secretName: gcp-credentials
        items:
        - key: sa_json
          path: credentials.json
```

Append one more volume entry to that `value:` list (after `gcp-credentials`):

```yaml
    - name: actions
      configMap:
        name: kopia-actions
        defaultMode: 0755
```

- [ ] **Step 3: Add the `actions` volumeMount in `backup-documents` patch**

In the same file, the container `volumeMounts` patch lists `backup`, `config`, `gcp-credentials` under:

```yaml
- op: add
  path: "/spec/template/spec/containers/0/volumeMounts"
  value:
    - name: backup
      mountPath: /Volumes/Documents # Mimics OSX path
      readOnly: true
    - name: config
      mountPath: /app
      readOnly: false
    - name: gcp-credentials
      mountPath: /tmp/gcp
      readOnly: true
```

Append one more mount entry to that `value:` list (after `gcp-credentials`):

```yaml
    - name: actions
      mountPath: /app/actions
      readOnly: true
```

- [ ] **Step 4: Apply the same two additions to the `backup-photos` patch**

In `k8s/namespaces/backup-photos/patches/deployment.yaml`, append the identical `actions` volume entry to its `/spec/template/spec/volumes` `value:` list:

```yaml
    - name: actions
      configMap:
        name: kopia-actions
        defaultMode: 0755
```

and the identical `actions` mount to its `/spec/template/spec/containers/0/volumeMounts` `value:` list:

```yaml
    - name: actions
      mountPath: /app/actions
      readOnly: true
```

(The photos `backup` mount uses `mountPath: /Volumes/Photos`; leave that and all other entries unchanged.)

- [ ] **Step 5: Verify mount + reference rewrite in both overlays**

Run: `kustomize build k8s/namespaces/backup-documents | grep -c 'mountPath: /app/actions'`
Expected: `1`

Run: `kustomize build k8s/namespaces/backup-photos | grep -c 'mountPath: /app/actions'`
Expected: `1`

Confirm the volume points at the hashed ConfigMap name (reference rewriting worked) and the volume name `actions` is unique:
Run: `kustomize build k8s/namespaces/backup-documents | grep -B1 'name: kopia-actions-'`
Expected: a line showing the `configMap:` block under a volume named `actions`, referencing `kopia-actions-<hash>`.

Run: `kustomize build k8s/namespaces/backup-documents >/dev/null && kustomize build k8s/namespaces/backup-photos >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add k8s/namespaces/backup-documents/patches/deployment.yaml k8s/namespaces/backup-photos/patches/deployment.yaml
git commit -m "feat(kopia): mount Chronos action scripts into backup deployments"
```

---

### Task 5: Document manual Chronos / 1Password setup

**Files:**
- Modify: `k8s/bases/kopia/README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: documentation only. No build impact.

- [ ] **Step 1: Append a "Chronos health checks" section to `k8s/bases/kopia/README.md`**

Add this section at the end of the file:

```markdown
## Chronos Health Checks (manual, one-time)

Each backup pings the Chronos job health-check system via Kopia Actions:
`before-snapshot-root` → `start`, `after-snapshot-root` → `success`. A failed or
missed snapshot is detected by Chronos when the expected `success` ping never
arrives (dead-man), so each job MUST have an expected schedule and grace period.

1. In the Chronos UI (`https://chronos.bruner.family`) create two jobs:
   one for documents, one for photos. For each, set an **expected schedule**
   matching the policy crontab `15 4 * * *` (America/Chicago) and a **grace
   period** long enough to cover the longest expected backup runtime.
2. For each job, copy its ping **token** into a 1Password item in vault `lab`,
   stored in a field named `token`:
   - `Chronos Backup Documents`  → consumed by `backup-documents`
   - `Chronos Backup Photos`      → consumed by `backup-photos`
   The overlays' `resources/chronos.yaml` `OnePasswordItem` resources point at
   these items and materialize a `chronos` secret (key `token`) per namespace.
3. Push to git; ArgoCD syncs. The init container sets the action hooks on the
   policy idempotently, and the server runs with `--enable-actions`.

Pings are best-effort (`curl -m 10`, `--action-command-mode=optional`): a
Chronos outage never blocks or fails a backup. The Chronos run id (`rid`) is
Kopia's `KOPIA_SNAPSHOT_ID`, which links the `start` and `success` pings.
```

- [ ] **Step 2: Commit**

```bash
git add k8s/bases/kopia/README.md
git commit -m "docs(kopia): document Chronos health-check setup"
```

---

## Final verification (after all tasks)

- [ ] Both overlays build cleanly:

```bash
kustomize build k8s/namespaces/backup-documents >/dev/null && \
kustomize build k8s/namespaces/backup-photos >/dev/null && echo "BOTH OK"
```
Expected: `BOTH OK`

- [ ] **Live checks (require cluster access; run after ArgoCD sync, not from the plan):**
  - Exec into a backup pod and run `kopia snapshot create "$BACKUP_TARGET"`; confirm a `start` then `success` ping appear for that job in Chronos with a computed duration (proves `KOPIA_SNAPSHOT_ID`-as-`rid` linking).
  - Confirm `kopia policy show "$BACKUP_TARGET"` lists the before/after action commands.
  - Negative: confirm a skipped scheduled run trips the Chronos grace alert.

## Out of scope

- No explicit `/fail` ping (no Kopia error hook for server-scheduled snapshots).
- No move from the Kopia internal scheduler to a Kubernetes CronJob wrapper.
- No change to the GCS repository, encryption, or the `15 4 * * *` schedule.
