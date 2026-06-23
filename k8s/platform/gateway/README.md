# Gateway

## Purpose

Provides the cluster's shared ingress layer. A single Envoy Gateway terminates TLS for all domains and routes traffic to backend services via Gateway API `HTTPRoute` resources.

## How it works

The Envoy Gateway Helm chart (v1.7.0, OCI) deploys the controller into `envoy-gateway-system`. Gateway API CRDs (v1.2.1) are installed as a kustomize remote resource. Key resources in this directory:

- **GatewayClass** (`envoy-gateway`) -- binds to the Envoy Gateway controller.
- **Gateway** (`shared-gateway` in `gateway-system`) -- single HTTPS listener on port 443 terminating TLS with per-domain certificate refs (argocd, grafana, prometheus, uptime, n8n, garage, dashboard), plus an HTTP listener on port 80 for redirect.
- **Certificates** -- per-domain TLS certificates in `certificates/` issued by cert-manager (`letsencrypt-prod`).
- **EnvoyProxy** (`proxy-config`) -- provides a stable service name for cloudflared to target.
- **HTTP-to-HTTPS redirect** -- global HTTPRoute redirecting port 80 to 443.

All `HTTPRoute` resources for individual services live in their respective app directories, not here.

## Dependencies

- **cert-manager** -- must be running to issue the TLS certificates referenced by the Gateway.
- **metallb** -- assigns LoadBalancer IPs to the Envoy proxy service.
- Sync-wave ordering: this component should sync after cert-manager.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `platform`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get gateways -n gateway-system
  kubectl get gatewayclass envoy-gateway
  kubectl get certificates -n gateway-system
  kubectl get httproutes -A
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n envoy-gateway-system -l app.kubernetes.io/name=gateway-helm --tail=50
  kubectl describe gateway shared-gateway -n gateway-system
  kubectl describe certificate <name> -n gateway-system
  ```
- **Common task -- add a TLS domain:**
  1. Create a Certificate in `certificates/<name>.yaml`.
  2. Add the `certificateRef` to `gateway.yaml`.
  3. Add the certificate file to `kustomization.yaml`.
  4. Commit and push.

## Secrets

None directly. TLS certificate secrets are created by cert-manager and referenced by the Gateway.
