# Crossplane HTTP Provider

Installs the Crossplane HTTP provider and its `ProviderConfig` for Cloudflare.

Bootstrap installs the **provider and credentials only**. All DNS records are managed by
ArgoCD via `k8s/namespaces/crossplane-system/`.

## Resources

- `resources/providers.yaml` — Crossplane `Provider` CRD (provider-http)
- `resources/secrets.yaml` — `OnePasswordItem` that syncs the Cloudflare API token into `crossplane-system/cloudflare`
- `resources/providerconfig.yaml` — `ProviderConfig` referencing the above secret

## Authentication

The Cloudflare API token is stored in 1Password (`vaults/lab/items/Cloudflare`) and injected
via the 1Password operator into the `cloudflare` Secret in `crossplane-system`. The
`ProviderConfig` reads the `token` key from that secret.
