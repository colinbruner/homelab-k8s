# crossplane-system

ArgoCD-managed Cloudflare DNS records, managed via the Crossplane HTTP provider.

The Crossplane operator and HTTP provider are installed via bootstrap
(`k8s/bootstrap/infra/`). This directory manages the DNS `Request` resources that
ArgoCD syncs, which in turn call the Cloudflare API to create and maintain A records.

## Architecture

```
values.yaml
    ↓ generate.sh (helm template)
resources/cloudflare/dns.yaml
    ↓ ArgoCD syncs
Crossplane Request CRDs
    ↓ HTTP provider
Cloudflare API (POST/GET/PATCH/DELETE)
```

One `Request` CRD is created per IP per hostname, named
`cloudflare-dns-{name}-{ip-dashes}` (e.g., `cloudflare-dns-argocd-192-168-10-240`).
This naming supports multiple A records per hostname for services with more than one IP.

## Managing DNS Records

All DNS records are defined in `values.yaml`. After editing, regenerate the manifests:

```bash
bash generate.sh
```

Then commit the updated `resources/cloudflare/dns.yaml`. ArgoCD syncs it automatically.

## Adding a New Record

Edit `values.yaml` and add an entry under `dns_records`:

```yaml
- name: "foo"          # subdomain (foo.colinbruner.com)
  content:             # one or more IPs — one A record per IP
    - "192.168.10.240"
  comment: "Foo service"
```

For a service with multiple IPs (DNS round-robin):

```yaml
- name: "foo"
  content:
    - "192.168.10.240"
    - "192.168.10.241"
  comment: "Foo service (multi-IP)"
```

Then run `bash generate.sh` and commit.

## IP Allocation

| Range | Assignment |
|---|---|
| `192.168.10.240` | Shared Envoy Gateway (HTTP/HTTPS for all web services) |
| `192.168.10.241` | SFTP direct LoadBalancer |
| `192.168.10.242–243` | Available for future direct LoadBalancer services |
