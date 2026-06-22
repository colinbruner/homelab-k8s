# cert-manager

Installs cert-manager and configures TLS certificate issuance via Let's Encrypt DNS-01 challenge over Cloudflare.

## Components

- **cert-manager Helm chart** (v1.16.2) — certificate controller with CRDs enabled
- **ClusterIssuers** — `letsencrypt-prod` and `letsencrypt-staging` for ACME DNS-01
- **OnePasswordItem** — `cloudflare` secret providing the Cloudflare API token from 1Password
