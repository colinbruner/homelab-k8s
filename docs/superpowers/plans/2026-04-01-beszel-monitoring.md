# Beszel Monitoring Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Beszel hub + agent monitoring across all 9 cluster nodes with OIDC auth, NFS storage, and public/internal access at `dashboard.colinbruner.com`.

**Architecture:** Single hub Deployment (PocketBase/SQLite) with a DaemonSet of agents on all nodes. Hub connects to agents via SSH. Exposed via Envoy Gateway HTTPRoute with TLS from cert-manager. OIDC via Pocket-ID, secrets from 1Password.

**Tech Stack:** Kustomize, Beszel (`henrygd/beszel`, `henrygd/beszel-agent`), ArgoCD (auto-discovery), cert-manager, 1Password operator, Crossplane (DNS), Cloudflare Tunnel.

**Spec:** `docs/superpowers/specs/2026-03-31-beszel-monitoring-design.md`

---

### Task 1: Create beszel namespace and kustomization scaffold

**Files:**
- Create: `k8s/namespaces/beszel/namespace.yaml`
- Create: `k8s/namespaces/beszel/kustomization.yaml`

- [ ] **Step 1: Create namespace manifest**

Create `k8s/namespaces/beszel/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: beszel
```

- [ ] **Step 2: Create initial kustomization.yaml**

Create `k8s/namespaces/beszel/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: beszel

resources:
  - namespace.yaml
```

- [ ] **Step 3: Validate kustomize build**

Run: `kustomize build k8s/namespaces/beszel/`

Expected: YAML output containing the Namespace resource, no errors.

- [ ] **Step 4: Commit**

```bash
git add k8s/namespaces/beszel/namespace.yaml k8s/namespaces/beszel/kustomization.yaml
git commit -m "feat(beszel): add namespace and kustomization scaffold"
```

---

### Task 2: Add hub PVC and 1Password secrets

**Files:**
- Create: `k8s/namespaces/beszel/resources/hub-pvc.yaml`
- Create: `k8s/namespaces/beszel/resources/onepassword-secret.yaml`
- Create: `k8s/namespaces/beszel/resources/onepassword-agent-key.yaml`
- Modify: `k8s/namespaces/beszel/kustomization.yaml`

- [ ] **Step 1: Create hub PVC**

Create `k8s/namespaces/beszel/resources/hub-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: beszel-hub-data
  namespace: beszel
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-csi
  resources:
    requests:
      storage: 5Gi
```

- [ ] **Step 2: Create 1Password OIDC secret**

Create `k8s/namespaces/beszel/resources/onepassword-secret.yaml`:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: beszel-oidc
spec:
  itemPath: "vaults/lab/items/beszel-oidc"
```

- [ ] **Step 3: Create 1Password agent key secret**

Create `k8s/namespaces/beszel/resources/onepassword-agent-key.yaml`:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: beszel-agent-key
spec:
  itemPath: "vaults/lab/items/beszel-agent-key"
```

- [ ] **Step 4: Add resources to kustomization.yaml**

Update `k8s/namespaces/beszel/kustomization.yaml` to:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: beszel

resources:
  - namespace.yaml
  - resources/hub-pvc.yaml
  - resources/onepassword-secret.yaml
  - resources/onepassword-agent-key.yaml
```

- [ ] **Step 5: Validate kustomize build**

Run: `kustomize build k8s/namespaces/beszel/`

Expected: YAML output containing Namespace, PVC, and two OnePasswordItem resources. No errors.

- [ ] **Step 6: Commit**

```bash
git add k8s/namespaces/beszel/resources/hub-pvc.yaml k8s/namespaces/beszel/resources/onepassword-secret.yaml k8s/namespaces/beszel/resources/onepassword-agent-key.yaml k8s/namespaces/beszel/kustomization.yaml
git commit -m "feat(beszel): add hub PVC and 1password secrets"
```

---

### Task 3: Add hub Deployment and Service

**Files:**
- Create: `k8s/namespaces/beszel/resources/hub-deployment.yaml`
- Create: `k8s/namespaces/beszel/resources/hub-service.yaml`
- Modify: `k8s/namespaces/beszel/kustomization.yaml`

- [ ] **Step 1: Create hub Deployment**

Create `k8s/namespaces/beszel/resources/hub-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: beszel-hub
  namespace: beszel
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: beszel-hub
  template:
    metadata:
      labels:
        app: beszel-hub
    spec:
      containers:
      - name: beszel
        image: henrygd/beszel:latest
        ports:
        - name: http
          containerPort: 8090
        env:
        - name: AUTH_OIDC_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: beszel-oidc
              key: client_id
        - name: AUTH_OIDC_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: beszel-oidc
              key: client_secret
        - name: AUTH_OIDC_AUTH_URL
          valueFrom:
            secretKeyRef:
              name: beszel-oidc
              key: auth_url
        - name: AUTH_OIDC_TOKEN_URL
          valueFrom:
            secretKeyRef:
              name: beszel-oidc
              key: token_url
        - name: AUTH_OIDC_USER_API_URL
          valueFrom:
            secretKeyRef:
              name: beszel-oidc
              key: user_api_url
        - name: AUTH_OIDC_DISPLAY_NAME
          value: "Pocket-ID"
        - name: AUTH_OIDC_REDIRECT_URL
          value: "https://dashboard.colinbruner.com/api/oauth2-redirect"
        - name: DISABLE_PASSWORD_AUTH
          value: "false"
        - name: USER_CREATION
          value: "false"
        volumeMounts:
        - name: data
          mountPath: /beszel_data
        readinessProbe:
          httpGet:
            path: /api/health
            port: 8090
          initialDelaySeconds: 10
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 8090
          initialDelaySeconds: 30
          periodSeconds: 30
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: beszel-hub-data
```

- [ ] **Step 2: Create hub Service**

Create `k8s/namespaces/beszel/resources/hub-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: beszel-hub
  namespace: beszel
spec:
  selector:
    app: beszel-hub
  ports:
  - name: http
    port: 8090
    targetPort: 8090
  type: ClusterIP
```

- [ ] **Step 3: Add resources to kustomization.yaml**

Update `k8s/namespaces/beszel/kustomization.yaml` to:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: beszel

resources:
  - namespace.yaml
  - resources/hub-pvc.yaml
  - resources/onepassword-secret.yaml
  - resources/onepassword-agent-key.yaml
  - resources/hub-deployment.yaml
  - resources/hub-service.yaml
```

- [ ] **Step 4: Validate kustomize build**

Run: `kustomize build k8s/namespaces/beszel/`

Expected: YAML output containing Namespace, PVC, two OnePasswordItems, Deployment, and Service. No errors.

- [ ] **Step 5: Commit**

```bash
git add k8s/namespaces/beszel/resources/hub-deployment.yaml k8s/namespaces/beszel/resources/hub-service.yaml k8s/namespaces/beszel/kustomization.yaml
git commit -m "feat(beszel): add hub deployment and service"
```

---

### Task 4: Add agent DaemonSet

**Files:**
- Create: `k8s/namespaces/beszel/resources/agent-daemonset.yaml`
- Modify: `k8s/namespaces/beszel/kustomization.yaml`

- [ ] **Step 1: Create agent DaemonSet**

Create `k8s/namespaces/beszel/resources/agent-daemonset.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: beszel-agent
  namespace: beszel
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  selector:
    matchLabels:
      app: beszel-agent
  template:
    metadata:
      labels:
        app: beszel-agent
    spec:
      hostNetwork: true
      hostPID: true
      dnsPolicy: ClusterFirstWithHostNet
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: beszel-agent
        image: henrygd/beszel-agent:latest
        env:
        - name: KEY
          valueFrom:
            secretKeyRef:
              name: beszel-agent-key
              key: public_key
        - name: PORT
          value: "45876"
        - name: DOCKER_HOST
          value: "unix:///run/containerd/containerd.sock"
        - name: LOG_LEVEL
          value: "warn"
        ports:
        - name: agent
          containerPort: 45876
          hostPort: 45876
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: os-release
          mountPath: /host/etc/os-release
          readOnly: true
        - name: containerd-sock
          mountPath: /run/containerd/containerd.sock
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      - name: os-release
        hostPath:
          path: /etc/os-release
      - name: containerd-sock
        hostPath:
          path: /run/containerd/containerd.sock
```

- [ ] **Step 2: Add resource to kustomization.yaml**

Update `k8s/namespaces/beszel/kustomization.yaml` to:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: beszel

resources:
  - namespace.yaml
  - resources/hub-pvc.yaml
  - resources/onepassword-secret.yaml
  - resources/onepassword-agent-key.yaml
  - resources/hub-deployment.yaml
  - resources/hub-service.yaml
  - resources/agent-daemonset.yaml
```

- [ ] **Step 3: Validate kustomize build**

Run: `kustomize build k8s/namespaces/beszel/`

Expected: YAML output containing all previous resources plus the DaemonSet. No errors.

- [ ] **Step 4: Commit**

```bash
git add k8s/namespaces/beszel/resources/agent-daemonset.yaml k8s/namespaces/beszel/kustomization.yaml
git commit -m "feat(beszel): add agent daemonset for all 9 nodes"
```

---

### Task 5: Add HTTPRoute for dashboard access

**Files:**
- Create: `k8s/namespaces/beszel/resources/httproute.yaml`
- Modify: `k8s/namespaces/beszel/kustomization.yaml`

- [ ] **Step 1: Create HTTPRoute**

Create `k8s/namespaces/beszel/resources/httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: beszel
  namespace: beszel
spec:
  parentRefs:
  - name: shared-gateway
    namespace: gateway-system
    sectionName: https
  hostnames:
  - dashboard.colinbruner.com
  - dashboard-internal.colinbruner.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: beszel-hub
      port: 8090
```

- [ ] **Step 2: Add resource to kustomization.yaml**

Update `k8s/namespaces/beszel/kustomization.yaml` to:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: beszel

resources:
  - namespace.yaml
  - resources/hub-pvc.yaml
  - resources/onepassword-secret.yaml
  - resources/onepassword-agent-key.yaml
  - resources/hub-deployment.yaml
  - resources/hub-service.yaml
  - resources/agent-daemonset.yaml
  - resources/httproute.yaml
```

- [ ] **Step 3: Validate kustomize build**

Run: `kustomize build k8s/namespaces/beszel/`

Expected: YAML output containing all resources including HTTPRoute. No errors.

- [ ] **Step 4: Commit**

```bash
git add k8s/namespaces/beszel/resources/httproute.yaml k8s/namespaces/beszel/kustomization.yaml
git commit -m "feat(beszel): add httproute for dashboard access"
```

---

### Task 6: Add TLS certificate and gateway listener

**Files:**
- Create: `k8s/namespaces/gateway-system/resources/certificates/dashboard.yaml`
- Modify: `k8s/namespaces/gateway-system/resources/gateway.yaml`
- Modify: `k8s/namespaces/gateway-system/kustomization.yaml`

- [ ] **Step 1: Create TLS certificate**

Create `k8s/namespaces/gateway-system/resources/certificates/dashboard.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dashboard-tls
  namespace: gateway-system
spec:
  secretName: dashboard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - dashboard.colinbruner.com
  - dashboard-internal.colinbruner.com
```

- [ ] **Step 2: Add certificate ref to shared gateway**

In `k8s/namespaces/gateway-system/resources/gateway.yaml`, add `dashboard-tls` to the HTTPS listener's `certificateRefs` list. The full `certificateRefs` section becomes:

```yaml
      certificateRefs:
      - kind: Secret
        name: argocd-tls
      - kind: Secret
        name: grafana-tls
      - kind: Secret
        name: prometheus-tls
      - kind: Secret
        name: uptime-tls
      - kind: Secret
        name: n8n-tls
      - kind: Secret
        name: garage-tls
      - kind: Secret
        name: dashboard-tls
```

- [ ] **Step 3: Add certificate to gateway-system kustomization**

In `k8s/namespaces/gateway-system/kustomization.yaml`, add to the resources list:

```yaml
  - resources/certificates/dashboard.yaml
```

The full resources list becomes:

```yaml
resources:
  - resources/envoy-proxy.yaml
  - resources/gateway.yaml
  - resources/http-redirect.yaml
  - resources/certificates/argocd.yaml
  - resources/certificates/grafana.yaml
  - resources/certificates/prometheus.yaml
  - resources/certificates/uptime.yaml
  - resources/certificates/n8n.yaml
  - resources/certificates/garage.yaml
  - resources/certificates/dashboard.yaml
```

- [ ] **Step 4: Validate kustomize build for gateway-system**

Run: `kustomize build k8s/namespaces/gateway-system/`

Expected: YAML output containing all gateway resources plus the new dashboard Certificate. No errors.

- [ ] **Step 5: Commit**

```bash
git add k8s/namespaces/gateway-system/resources/certificates/dashboard.yaml k8s/namespaces/gateway-system/resources/gateway.yaml k8s/namespaces/gateway-system/kustomization.yaml
git commit -m "feat(gateway-system): add dashboard TLS certificate and listener"
```

---

### Task 7: Add internal DNS record via Crossplane

**Files:**
- Modify: `k8s/namespaces/crossplane-system/values.yaml`
- Regenerate: `k8s/namespaces/crossplane-system/resources/cloudflare/` (via `generate.sh`)

- [ ] **Step 1: Add dashboard-internal DNS record**

In `k8s/namespaces/crossplane-system/values.yaml`, add a new entry to the `dns_records` list, after the `garage-admin-internal` entry and before the `# -- Direct LoadBalancer services --` comment:

```yaml
      - name: "dashboard-internal"
        content:
          - "192.168.10.240"
          - "192.168.10.241"
          - "192.168.10.242"
        comment: "Internal Beszel Dashboard (multi-IP)"
```

- [ ] **Step 2: Regenerate Crossplane resources**

Run: `cd k8s/namespaces/crossplane-system && bash generate.sh && cd -`

Expected: Files regenerated in `k8s/namespaces/crossplane-system/resources/cloudflare/`. No errors.

- [ ] **Step 3: Validate kustomize build for crossplane-system**

Run: `kustomize build k8s/namespaces/crossplane-system/`

Expected: YAML output containing all Crossplane resources including the new `dashboard-internal` DNS record. No errors.

- [ ] **Step 4: Commit**

```bash
git add k8s/namespaces/crossplane-system/values.yaml k8s/namespaces/crossplane-system/resources/cloudflare/
git commit -m "feat(crossplane): add dashboard-internal DNS A record"
```

---

### Task 8: Manual post-deploy steps (documentation only)

These steps require cluster access and cannot be automated via manifests. They should be performed after Tasks 1-7 are pushed and ArgoCD has synced.

- [ ] **Step 1: Create 1Password items**

Create two items in the `lab` vault:

1. **`beszel-oidc`** — fields: `client_id`, `client_secret`, `auth_url`, `token_url`, `user_api_url` (values from Pocket-ID OIDC provider configuration for a new Beszel client)
2. **`beszel-agent-key`** — field: `public_key` (populated in Step 3 below, leave empty initially)

- [ ] **Step 2: Register public DNS via Cloudflare Tunnel**

Run: `cloudflared tunnel route dns homelab dashboard.colinbruner.com`

This creates a CNAME record pointing `dashboard.colinbruner.com` to the tunnel.

- [ ] **Step 3: Extract SSH key and store in 1Password**

1. Access `https://dashboard.colinbruner.com` or `https://dashboard-internal.colinbruner.com`
2. Complete initial admin setup (create first user via OIDC)
3. Click "Add System" in the hub UI
4. Copy the Ed25519 public key displayed
5. Update the `beszel-agent-key` item in 1Password: set `public_key` field to the copied key
6. Wait for 1Password operator to sync the secret (~1-2 minutes)

- [ ] **Step 4: Register all 9 nodes in the hub**

In the hub UI, add each node as a system:
- Use the node's IP address and port `45876`
- Repeat for all 3 control plane nodes and 6 worker nodes
- Verify metrics start appearing for each system

- [ ] **Step 5: Lock down password auth**

Once OIDC login is confirmed working, update `k8s/namespaces/beszel/resources/hub-deployment.yaml`:

Change `DISABLE_PASSWORD_AUTH` from `"false"` to `"true"`:

```yaml
        - name: DISABLE_PASSWORD_AUTH
          value: "true"
```

Commit and push — ArgoCD will sync the change.
