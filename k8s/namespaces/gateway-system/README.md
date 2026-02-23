# Gateway System

ArgoCD-managed resources for the shared Envoy Gateway.

The Envoy Gateway controller and Gateway API CRDs are installed via bootstrap (`k8s/bootstrap/network/02-gateway/`). This directory manages the application-level resources that ArgoCD syncs:

- **Gateway** (`resources/gateway.yaml`) — Shared `Gateway` with HTTP (:80) and HTTPS (:443) listeners. The HTTPS listener terminates TLS using per-domain certificate refs.
- **HTTP Redirect** (`resources/http-redirect.yaml`) — Global `HTTPRoute` that 301-redirects all HTTP traffic to HTTPS.
- **TLS Certificates** (`resources/certificates/`) — cert-manager `Certificate` CRDs, one per domain. Each generates a TLS `Secret` referenced by the Gateway.

## Adding a New Service

To expose `foo.colinbruner.com`:

1. Create `resources/certificates/foo.yaml`:
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: foo-tls
     namespace: gateway-system
   spec:
     secretName: foo-tls
     issuerRef:
       name: letsencrypt-prod
       kind: ClusterIssuer
     dnsNames:
     - foo.colinbruner.com
   ```

2. Add `certificateRef` to the HTTPS listener in `resources/gateway.yaml`:
   ```yaml
   - kind: Secret
     name: foo-tls
   ```

3. Add the certificate to `kustomization.yaml`:
   ```yaml
   - resources/certificates/foo.yaml
   ```

4. Create an `HTTPRoute` in `k8s/namespaces/foo/httproute.yaml` pointing to the backend service.

5. Push to `main` — ArgoCD syncs everything automatically.
