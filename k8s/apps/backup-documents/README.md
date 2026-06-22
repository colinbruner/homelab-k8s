# backup-documents

Kopia backup of the UNAS Documents share to Google Cloud Storage (GCS).

## Secrets

- **`gcp-credentials`** (key: `sa_json`) — GCP service account JSON for GCS access.
  This is a **manual** secret that must be created in the `backup-documents` namespace
  before the backup can run. It is NOT stored in git.
- **`backup`** (key: `password`) — Kopia repository password. Provisioned automatically
  via OnePasswordItem.
- **`chronos`** (key: `token`) — Chronos health-check token. Provisioned automatically
  via OnePasswordItem.
