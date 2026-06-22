# gateway

Installs Envoy Gateway with Gateway API CRDs and configures a shared Gateway that terminates TLS for all domains.

## Components

- **Gateway API CRDs** (v1.2.1) — standard CRDs installed as a kustomize remote resource
- **Envoy Gateway Helm chart** (v1.7.0) — controller in `envoy-gateway-system` with EnvoyPatchPolicy extension enabled
- **GatewayClass** — `envoy-gateway` class for the Envoy Gateway controller
- **Gateway** — `shared-gateway` in `gateway-system` terminating TLS for all domains
- **Certificates** — per-domain TLS certificates (argocd, grafana, prometheus, uptime, n8n, garage, dashboard) via cert-manager
- **EnvoyProxy** — `proxy-config` providing a stable service name for cloudflared
- **HTTP-to-HTTPS redirect** — global HTTPRoute redirecting port 80 to 443
