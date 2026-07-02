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
