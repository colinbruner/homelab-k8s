# platform/crossplane

Crossplane operator with the HTTP provider, managing Cloudflare internal DNS A records via GitOps.

## Architecture

The Crossplane Helm chart deploys the operator. The HTTP provider (`provider-http`) and
its `ProviderConfig` (`http-cloudflare`) authenticate against the Cloudflare API using a
1Password-injected secret.

Internal DNS A records are defined in `values.yaml` and rendered by `generate.sh` into
`resources/cloudflare/` as Crossplane `Request` CRDs. ArgoCD syncs these automatically.

## Managing DNS Records

Edit `values.yaml`, then regenerate:

```bash
bash generate.sh
```

Commit the updated `resources/cloudflare/dns.yaml`.

## Cutover Warning

The Crossplane chart is pinned to **2.3.2** (app v2.x). The legacy bootstrap install
(`k8s/bootstrap/infra/crossplane/install.sh`) was unpinned. If the live cluster runs
Crossplane 1.x, switching to this platform definition is a **major version upgrade**.
Verify the running version before cutover.
