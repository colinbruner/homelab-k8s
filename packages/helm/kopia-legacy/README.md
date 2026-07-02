# kopia Helm Chart

Parameterized Kopia GCS backup deployment. One `values.yaml` per backup
target (documents, photos, etc.) drives a complete Kopia server instance
that creates/connects a GCS repository, sets snapshot policies, and
optionally reports health via Chronos action hooks.

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `kopia/kopia` | Container image |
| `image.tag` | `0.23.1` | Pinned image tag |
| `target.name` | `""` | Target name (e.g. `documents`) -- drives PV/PVC names |
| `target.sourcePath` | `""` | Container mount path for the NFS backup source |
| `target.nfsPath` | `""` | NFS export path on the server |
| `target.schedule` | `15 4 * * *` | Kopia snapshot crontab |
| `target.description` | `""` | Repo description; defaults to `UNAS <Name> Backup` |
| `storage.gcsBucket` | `""` | GCS bucket name |
| `nfs.server` | `192.168.10.5` | NFS server address |
| `nfs.backupCapacity` | `1Ti` | Backup PV capacity |
| `nfs.backupRequest` | `1000Gi` | Backup PVC request |
| `nfs.configSize` | `50Gi` | Config PVC size (csi-nfs dynamic) |
| `chronos.enabled` | `true` | Enable Chronos health-check action hooks |
| `chronos.pingBase` | `https://chronos.bruner.family/ping` | Chronos ping base URL |
| `secrets.password.name` | `backup` | Secret name for kopia password (key: `password`) |
| `secrets.chronos.name` | `chronos` | Secret name for Chronos token (key: `token`) |
| `secrets.gcpCredentials.name` | `gcp-credentials` | Secret name for GCP SA (key: `sa_json`) |
| `resources` | `{requests: {cpu: 100m, memory: 50Mi}, limits: {cpu: 1000m, memory: 1Gi}}` | Pod resources |

## External Secret Dependency: gcp-credentials

This chart mounts a Kubernetes Secret named by `secrets.gcpCredentials.name`
(default: `gcp-credentials`) with key `sa_json` containing a GCP service
account JSON credential file. **This secret is NOT created by this chart.**
It must already exist in the target namespace before the Helm release is
installed.

The secret is not defined in the old Kustomize base or overlays either --
it is provisioned externally (e.g. via a OnePasswordItem or manual creation).
Each app namespace overlay that consumes this chart must ensure the
`gcp-credentials` secret exists.
