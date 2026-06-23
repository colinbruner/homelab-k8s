# Crossplane

## Purpose

Manages internal Cloudflare DNS A records via GitOps. Services exposed on the LAN get `*-internal.colinbruner.com` A records pointing to the MetalLB pool, all defined declaratively in this directory.

## How it works

The Crossplane Helm chart (v2.3.2) deploys the operator into `crossplane-system`. The HTTP provider (`provider-http` v1.0.8) and its `ProviderConfig` (`http-cloudflare`) authenticate against the Cloudflare API using the `cloudflare` secret (key: `token`) in the `crossplane-system` namespace.

Internal DNS A records are defined in `values.yaml` and rendered by `generate.sh` (which runs `helm template` against the local `packages/helm/cloudflare` chart) into `resources/cloudflare/dns.yaml` as Crossplane HTTP `Request` CRDs. ArgoCD syncs these automatically.

## Dependencies

- **1password** -- the `cloudflare` secret in `crossplane-system` must exist (the ProviderConfig references it). This secret needs to be provisioned in this namespace (separate from cert-manager's copy).
- **cert-manager** -- not a direct dependency, but shares the same Cloudflare API token pattern.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `platform`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get providers.pkg.crossplane.io
  kubectl get providerconfigs.http.crossplane.io
  kubectl get requests.http.crossplane.io -n crossplane-system
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n crossplane-system -l app=crossplane --tail=50
  kubectl describe request <name> -n crossplane-system
  ```
- **Common task -- add an internal DNS record:**
  1. Edit `values.yaml` and add the new record entry.
  2. Run `bash generate.sh` to re-render `resources/cloudflare/dns.yaml`.
  3. Commit and push -- ArgoCD syncs the change.

## Cutover warning

The Crossplane chart is pinned to **2.3.2** (app v2.x). The legacy bootstrap install was unpinned. If the live cluster runs Crossplane 1.x, switching to this platform definition is a major version upgrade. Verify the running version before cutover:

```bash
kubectl get deployment crossplane -n crossplane-system -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `cloudflare` | `token` | Must exist in `crossplane-system` namespace. Provisioned via OnePasswordItem or manually copied from the cert-manager namespace secret. |
