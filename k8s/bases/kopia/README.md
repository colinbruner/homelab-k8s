# Backups

Using Kopia for encrypted backups to GCS buckets.

## Layout

I really did not want to write another helm chart, so I tried out the Kustomize base / overlay pattern. The [base](./base/) directory is used in all overlays as "base" resources. From this, we inject some patches and add some additional overlay specific resources.

## Manual

Currently, there is a secret that must be manually created (not checked into git) that defines the json keys of the service account that kopia uses to connect to the GCS bucket.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: credentials-secret
type: Opaque
stringData:
  sa_json: |
    {
      "type": "service_account",
    ...
```

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
