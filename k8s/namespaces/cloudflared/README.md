# Cloudflare Tunnel (cloudflared) + Envoy Gateway + Authentik

## Architecture Overview

```
Internet
    |
    v
Cloudflare Edge (TLS termination, DDoS, WAF, bot protection)
    |  (Cloudflare Tunnel — encrypted QUIC/HTTP2)
    v
cloudflared pod (k8s, 2 replicas)
    |
    v
Envoy Gateway (shared-gateway, port 443)
    |
    +-- SecurityPolicy (ext_authz) --> Authentik Outpost
    |         |
    |         +-- 200 OK    --> forward to app
    |         +-- 401/302   --> redirect to auth.colinbruner.com
    |
    +-- HTTPRoute --> App pod (argocd, grafana, prometheus, n8n, etc.)
```

### Traffic Flows

**Public access (via Cloudflare Tunnel):**
```
User --> argocd.colinbruner.com
     --> Cloudflare Edge (CNAME to <TUNNEL_ID>.cfargotunnel.com)
     --> Tunnel (encrypted)
     --> cloudflared pod
     --> Envoy Gateway (HTTPS, noTLSVerify)
     --> [SecurityPolicy ext_authz check]
     --> HTTPRoute --> argocd-server pod
```

**Internal/LAN access (direct):**
```
User --> argocd-internal.colinbruner.com
     --> DNS A record (192.168.10.240/241/242)
     --> Envoy Gateway (HTTPS, TLS terminated with Let's Encrypt cert)
     --> [SecurityPolicy ext_authz check]
     --> HTTPRoute --> argocd-server pod
```

## DNS Naming Convention

| Access Path | DNS Pattern | Record Type | Target |
|---|---|---|---|
| **Public** (tunnel) | `<name>.colinbruner.com` | CNAME | `<TUNNEL_ID>.cfargotunnel.com` |
| **Internal** (LAN) | `<name>-internal.colinbruner.com` | A | `192.168.10.240/241/242` |

The `-internal` A records are managed via Crossplane in `k8s/namespaces/crossplane-system/`.
The public CNAME records are managed via Cloudflare (dashboard or CLI).

---

## Manual Setup Steps (Cloudflare Dashboard)

### Step 1: Create a Cloudflare Tunnel

1. Log in to the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks > Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** as the connector type
5. Name the tunnel (e.g., `homelab-k8s`)
6. **Save the tunnel credentials** — you will get:
   - A `credentials.json` file containing:
     ```json
     {
       "AccountTag": "<ACCOUNT_ID>",
       "TunnelSecret": "<BASE64_SECRET>",
       "TunnelID": "<TUNNEL_UUID>"
     }
     ```
   - A tunnel token (for alternative auth methods)
7. **Do not configure public hostnames in the dashboard** — we manage routing
   via the local config file in Kubernetes

### Step 2: Store Tunnel Credentials in 1Password

Create a 1Password item at `vaults/lab/items/cloudflared-tunnel` with:

| Field | Value |
|---|---|
| `credentials.json` | The full JSON content from Step 1 |

The OnePasswordItem CRD will create a Kubernetes Secret with this data,
mounted into the cloudflared pods.

### Step 3: Update the Tunnel ID in ConfigMap

Edit `resources/configmap.yaml` and replace `TUNNEL_ID` with the actual
tunnel UUID from Step 1:

```yaml
data:
  config.yaml: |
    tunnel: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  # <-- your tunnel UUID
```

### Step 4: Verify the Envoy Proxy Service Name

The cloudflared config routes traffic to the Envoy Gateway proxy service.
Verify the correct service name:

```bash
kubectl get svc -n envoy-gateway-system
```

Update the `service` field in `resources/configmap.yaml` if the service name
differs from `envoy-gateway-system-shared-gateway`.

### Step 5: Create DNS CNAME Records

Since we use a locally-managed config file (not the Cloudflare dashboard),
DNS CNAME records are **not** created automatically. Create them using the CLI:

```bash
# Install cloudflared locally if not already installed
# https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/

# Route each public hostname to the tunnel
cloudflared tunnel route dns homelab-k8s argocd.colinbruner.com
cloudflared tunnel route dns homelab-k8s grafana.colinbruner.com
cloudflared tunnel route dns homelab-k8s prometheus.colinbruner.com
cloudflared tunnel route dns homelab-k8s n8n.colinbruner.com
cloudflared tunnel route dns homelab-k8s auth.colinbruner.com
cloudflared tunnel route dns homelab-k8s garage.colinbruner.com
cloudflared tunnel route dns homelab-k8s garage-admin.colinbruner.com
cloudflared tunnel route dns homelab-k8s uptime.colinbruner.com
```

Each command creates a CNAME record: `<hostname>` -> `<TUNNEL_ID>.cfargotunnel.com`.

Alternatively, create these CNAME records manually in the Cloudflare DNS dashboard,
or via the Cloudflare API.

> **Important:** The old A records pointing to private IPs (192.168.10.240-242) have
> been renamed to `*-internal.colinbruner.com`. Ensure these old A records are deleted
> from Cloudflare before creating the new CNAME records, as a hostname cannot have both
> an A and a CNAME record.

### Step 6: Configure Cloudflare Zero Trust Access Policies (Optional)

For additional security beyond Authentik, configure Cloudflare Access policies:

1. Navigate to **Access > Applications** in Zero Trust Dashboard
2. Create a **Self-hosted application** per service
3. Configure Access policies (e.g., email domain, IdP integration)
4. This adds a second layer of authentication at the Cloudflare edge

---

## Authentik ext_authz Configuration

### How Forward Authentication Works

```
1. User requests https://prometheus.colinbruner.com
2. Request arrives at Envoy Gateway via cloudflared tunnel
3. Envoy's ext_authz filter sends a check request to Authentik:
   GET /outpost.goauthentik.io/auth/nginx
   Headers: Cookie, Authorization, X-Forwarded-* (from original request)
4a. If valid session exists:
    - Authentik returns 200 OK
    - Authentik adds headers: X-authentik-username, X-authentik-groups, etc.
    - Envoy forwards these headers to the backend
    - Request proceeds to the app
4b. If no valid session:
    - Authentik returns 401 with Location header
    - Envoy returns the 401 to the client
    - Browser follows redirect to: https://auth.colinbruner.com/outpost.goauthentik.io/start?rd=<original-url>
    - User authenticates via Authentik (local credentials, Google OAuth, etc.)
    - Authentik sets session cookie on .colinbruner.com domain
    - User is redirected back to the original URL
    - The session cookie is now present, so step 4a succeeds
```

### Authentik Admin Setup

For each service you want to protect:

#### 1. Create a Proxy Provider

1. Go to **Authentik Admin > Applications > Providers**
2. Create a new **Proxy Provider**
3. Set **Authorization flow** to `default-provider-authorization-implicit-consent`
4. Set **Forward auth mode** to **Forward auth (single application)**
5. Set **External host** to the service URL (e.g., `https://prometheus.colinbruner.com`)

#### 2. Create an Application

1. Go to **Authentik Admin > Applications > Applications**
2. Create a new Application
3. Link it to the Proxy Provider created above
4. Set the **Launch URL** to the service URL

#### 3. Assign to the Embedded Outpost

1. Go to **Authentik Admin > Applications > Outposts**
2. Edit the **Embedded Outpost** (authentik Embedded Outpost)
3. Add the new Application to the outpost's application list

### Creating SecurityPolicy for Additional Services

To protect a new service with Authentik ext_authz:

1. **Add the namespace to the ReferenceGrant** in `k8s/namespaces/authentik/reference-grant.yaml`:
   ```yaml
   from:
   - group: gateway.envoyproxy.io
     kind: SecurityPolicy
     namespace: <new-namespace>
   ```

2. **Create a SecurityPolicy** in the service's namespace:
   ```yaml
   apiVersion: gateway.envoyproxy.io/v1alpha1
   kind: SecurityPolicy
   metadata:
     name: authentik-ext-auth-<service>
     namespace: <namespace>
   spec:
     targetRefs:
     - group: gateway.networking.k8s.io
       kind: HTTPRoute
       name: <httproute-name>
     extAuth:
       http:
         backendRefs:
         - name: authentik-server
           namespace: authentik
           port: 80
         headersToBackend:
         - X-authentik-username
         - X-authentik-groups
         - X-authentik-email
         - X-authentik-name
         - X-authentik-uid
         path: /outpost.goauthentik.io/auth/nginx
   ```

3. **Add the SecurityPolicy to the namespace's kustomization.yaml**

4. **Create the Authentik Application + Provider** (see Authentik Admin Setup above)

### Services That Should NOT Have ext_authz

| Service | Reason |
|---|---|
| `auth.colinbruner.com` (Authentik) | Circular dependency — Authentik cannot authenticate itself |
| `argocd.colinbruner.com` | Has its own RBAC and authentication system |

### Services That Benefit from ext_authz

| Service | Reason |
|---|---|
| `prometheus.colinbruner.com` | No built-in authentication (already configured) |
| `grafana.colinbruner.com` | Has built-in auth, but SSO provides unified login |
| `n8n.colinbruner.com` | Additional security layer for workflow automation |
| `garage.colinbruner.com` | Additional security for S3 web interface |
| `garage-admin.colinbruner.com` | Protects admin API |

---

## Security Best Practices

### Defense in Depth

This architecture implements multiple security layers:

1. **Cloudflare Edge (Layer 1)**
   - DDoS protection
   - WAF (Web Application Firewall)
   - Bot management
   - TLS termination with Cloudflare-managed certificates
   - IP reputation filtering
   - Rate limiting (configurable per-rule)

2. **Cloudflare Tunnel (Layer 2)**
   - No open inbound ports on the homelab network
   - Encrypted tunnel (QUIC/HTTP2) from cluster to Cloudflare edge
   - Tunnel credentials authenticate the connector to Cloudflare
   - Only traffic matching configured CNAME records reaches the tunnel

3. **Cloudflare Access (Layer 3, optional)**
   - Zero Trust access policies at the edge
   - IdP integration (Google, GitHub, SAML, etc.)
   - Device posture checks
   - Geo-restrictions

4. **Authentik ext_authz (Layer 4)**
   - SSO across all services via Envoy Gateway SecurityPolicy
   - Centralized user management and RBAC
   - MFA support (TOTP, WebAuthn, etc.)
   - Session management with configurable timeouts
   - Social login (Google OAuth2, GitHub)
   - Audit logging

5. **Application-level Auth (Layer 5)**
   - Service-specific authentication (ArgoCD RBAC, Grafana roles)
   - API tokens for automation

### Network Security

- **No public IPs exposed**: The homelab has zero inbound ports open.
  All public traffic flows through the Cloudflare tunnel.
- **Internal DNS separation**: LAN clients use `*-internal.colinbruner.com`
  A records pointing to MetalLB IPs, completely bypassing Cloudflare.
- **Pod-to-pod encryption**: cloudflared connects to Envoy Gateway via HTTPS.
  Consider enabling strict TLS verification in production.

### Secret Management

- **Tunnel credentials**: Stored in 1Password, injected via OnePasswordItem CRD
- **TLS certificates**: Managed by cert-manager with Let's Encrypt (DNS-01 via Cloudflare)
- **Authentik secrets**: Stored in 1Password (secret key, DB password, OAuth credentials)
- **No secrets in git**: All sensitive values are referenced, never committed

### Operational Security

- **cloudflared replicas**: Running 2 replicas for high availability
- **Health checks**: Liveness and readiness probes on the `/ready` endpoint
- **Metrics**: Prometheus-compatible metrics exposed on port 2000
- **Image pinning**: Use specific image tags (e.g., `2025.2.1`) instead of `latest`
- **Resource limits**: CPU and memory limits prevent resource exhaustion
- **Fail closed**: ext_authz denies requests when Authentik is unreachable (secure default)

### Cloudflare API Token Permissions

For the Cloudflare API token used by cert-manager (DNS-01 challenges) and
tunnel management, use the minimum required permissions:

| Permission | Scope | Purpose |
|---|---|---|
| `Zone:DNS:Edit` | Specific zone (colinbruner.com) | cert-manager DNS-01 challenges |
| `Zone:Zone:Read` | Specific zone | cert-manager zone lookup |
| `Account:Cloudflare Tunnel:Edit` | Account | Tunnel management |
| `Account:Cloudflare Tunnel:Read` | Account | Tunnel status |

Create separate API tokens for different purposes (cert-manager vs tunnel management)
following the principle of least privilege.

---

## Exposing a New Public Service

To expose a new service `foo.colinbruner.com`:

1. **Certificate**: Update `k8s/namespaces/gateway-system/resources/certificates/foo.yaml`
   to include both public and internal SANs:
   ```yaml
   dnsNames:
   - foo.colinbruner.com
   - foo-internal.colinbruner.com
   ```

2. **Gateway listener**: Add `certificateRef` to `k8s/namespaces/gateway-system/resources/gateway.yaml`

3. **Kustomization**: Add cert to `k8s/namespaces/gateway-system/kustomization.yaml`

4. **HTTPRoute**: Add both hostnames to the route:
   ```yaml
   hostnames:
   - foo.colinbruner.com
   - foo-internal.colinbruner.com
   ```

5. **Internal DNS**: Add to `k8s/namespaces/crossplane-system/values.yaml`:
   ```yaml
   - name: "foo-internal"
     content:
       - "192.168.10.240"
       - "192.168.10.241"
       - "192.168.10.242"
     comment: "Internal Foo UI (multi-IP)"
   ```
   Then run: `bash k8s/namespaces/crossplane-system/generate.sh`

6. **Public DNS**: Create CNAME record:
   ```bash
   cloudflared tunnel route dns homelab-k8s foo.colinbruner.com
   ```

7. **SecurityPolicy** (optional): Add ext_authz per the instructions above

8. **Push to git**: ArgoCD syncs everything automatically

---

## Troubleshooting

### Check cloudflared tunnel status
```bash
kubectl logs -n cloudflared -l app=cloudflared --tail=50
kubectl get pods -n cloudflared
```

### Check tunnel metrics
```bash
kubectl port-forward -n cloudflared deploy/cloudflared 2000:2000
curl http://localhost:2000/metrics
```

### Verify Envoy proxy service name
```bash
kubectl get svc -n envoy-gateway-system
```

### Test ext_authz flow
```bash
# From within the cluster, test the Authentik auth endpoint
kubectl run -it --rm test --image=curlimages/curl -- \
  curl -v http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/nginx
```

### Check SecurityPolicy status
```bash
kubectl get securitypolicy -A
kubectl describe securitypolicy authentik-ext-auth-prometheus -n monitoring
```

### DNS verification
```bash
# Verify public CNAME
dig argocd.colinbruner.com CNAME

# Verify internal A record
dig argocd-internal.colinbruner.com A
```

### Certificate status
```bash
kubectl get certificates -n gateway-system
kubectl describe certificate argocd-tls -n gateway-system
```
