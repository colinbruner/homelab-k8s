# Kopia

This backs up my UNAS Storage to a GCS bucket with two layers of encryption.

# Manual

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

# Components

Kopia runs as a Server that connects to a Repository. The repository contains policies and tasks to backup local pathes as snapshots.

- Server: capable of acting as a Kopia Client (backup this to that), except handles schedules.
- Repository: stores the configuration for backups (policies, tasks, etc)
- Policies: Defines a path (to backup) and any additional overrides to global settings, such as compression format or scheduling timings
- Task: Actively running jobs creating snapshots or doing maintenance on existing files
- Snapshots: These are the backups.

# Configuration

There are a number of volumes defined that provide the necessary files, credentials, or configurations.

TODO: define volumes and their uses
