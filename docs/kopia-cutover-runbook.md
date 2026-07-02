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
   `onepassword-items.yaml`) and point the source's `repository:` at it.
4. Push; ArgoCD syncs. Verify the new policy:
   `kubectl -n backup exec deploy/backup-primary -c server -- kopia policy list`

## Storage-side hardening (follow-up, outside this repo)

Enable GCS object versioning / soft-delete on the bucket and scope the
service account to `roles/storage.objectAdmin` on this bucket only
(Terraform GCP workflow).
