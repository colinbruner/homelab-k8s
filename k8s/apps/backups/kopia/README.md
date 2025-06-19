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
