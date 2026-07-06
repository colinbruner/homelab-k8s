# Semaphore UI Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Semaphore UI as an ArgoCD-managed app so `homelab-automation`'s `site.yml` runs on a weekly schedule, with public + internal HTTPS exposure and Pocket ID (OIDC) login.

**Architecture:** A new `k8s/apps/semaphore/` app (auto-discovered by the apps ApplicationSet) runs a single-replica Deployment of the official `semaphoreui/semaphore` image with BoltDB on a dynamically-provisioned NFS PVC. Secrets arrive via a `OnePasswordItem` (admin password, access-key encryption key, read-only Connect token, Pocket ID client credentials). TLS terminates at the shared Envoy Gateway (new cert + listener ref in `k8s/platform/gateway/`); public traffic rides the existing cloudflared wildcard ingress rule. In-Semaphore configuration (Key Store, repo, templates, schedules) is manual per the canonical runbook.

**Tech Stack:** Kustomize, ArgoCD, Semaphore UI v2.18.20 (BoltDB), 1Password Operator/Connect, cert-manager, Envoy Gateway (Gateway API), csi-driver-nfs, Pocket ID (OIDC).

**Canonical spec:** `docs/semaphore.md` in the `homelab-automation` repo (branch `feat/semaphore-docs`, merging to `main`). Re-read it before executing; it overrides this plan on scheduling/config semantics.

## Global Constraints

- Image pin: `semaphoreui/semaphore:v2.18.20` (latest release as of 2026-07-05).
- No secrets in the repo — everything secret flows through `OnePasswordItem` CRDs from the `lab` vault.
- Ops playbooks (`ops/capacity-report.yml`, `ops/provision-worker.yml`, `ops/download-talos.yml`) get templates but must **never** be scheduled.
- Hostnames: `semaphore.colinbruner.com` (public, via tunnel) + `semaphore-internal.colinbruner.com` (LAN A record).
- OIDC provider: Pocket ID at `https://auth.colinbruner.com`, provider key `pocket-id`.
- 1Password Connect token for the pod must be scoped **read-only to the `lab` vault**.
- LF line endings; use `trash` instead of `rm`; branch from `main` (current checkout is on `fix/kopia-verify-chronos-ping`).
- Validation command for every manifest change (mirrors CI):

```bash
kustomize build --enable-helm <dir> \
  | kubeconform -strict -ignore-missing-schemas \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

**Known risk (accepted):** BoltDB uses mmap + flock; the only cluster storage is NFS (`nfs-csi-buckets` mounts with `nolock`). Single-writer is enforced with `replicas: 1` + `strategy: Recreate`. At homelab scale this is acceptable; the PVC is the only state and the repo/templates can be reconstructed from this plan if the DB ever corrupts.

---

### Task 1: Pre-flight — verify pod egress to lab management networks

The runbook requires verifying pods can reach `192.168.1.0/24` (Pis) and `192.168.10.0/24` (Proxmox/PXE) over SSH **before** installing Semaphore. Pods NAT through nodes; if this fails, fix routing/NetworkPolicy first and stop the plan.

**Files:** none (cluster verification only)

**Interfaces:**
- Produces: confirmed egress; go/no-go gate for all later tasks.

- [ ] **Step 1: Launch a debug pod and test SSH reachability on both subnets**

```bash
kubectl run -it --rm egress-test --image=busybox:1.36 --restart=Never -- sh -c '
  for host in 192.168.1.11 192.168.10.5; do
    if nc -z -w 5 "$host" 22; then echo "OK  $host:22"; else echo "FAIL $host:22"; fi
  done'
```

(Adjust the `192.168.1.x` IP to a real Pi from `homelab-automation`'s `ansible/inventory/` if `.11` is wrong — pick any root-login host on each subnet.)

Expected: `OK` for one host on each subnet, pod auto-deletes.

- [ ] **Step 2: Record the result**

If either line says `FAIL`, stop here — no manifests get written until egress works.

---

### Task 2: External prerequisites — Pocket ID client, Connect token, 1Password item, GitHub deploy key

All manual, no repo changes. Produces the 1Password item the manifests depend on.

**Files:** none

**Interfaces:**
- Produces: 1Password item `vaults/lab/items/semaphore` with field labels exactly: `admin-password`, `access-key-encryption`, `connect-token`, `oidc-client-id`, `oidc-client-secret`. Task 3's `OnePasswordItem` syncs these labels verbatim into a K8s Secret named `semaphore`.

- [ ] **Step 1: Create the Pocket ID OIDC client**

In the Pocket ID admin UI at `https://auth.colinbruner.com`: create a client named `semaphore` with callback URL:

```
https://semaphore.colinbruner.com/api/auth/oidc/pocket-id/redirect
```

Note the client ID and client secret. (OIDC login initiated from the internal hostname will redirect back to the public hostname — that is fine and expected since `redirect_url` is single-valued.)

- [ ] **Step 2: Create a read-only Connect token scoped to the `lab` vault**

```bash
op connect server list                      # get the Connect server name
op connect token create --help              # confirm the vault-permission syntax
op connect token create semaphore --server "<server-name>" --vault "lab,read_items"
```

The intent: token can read items in `lab` and nothing else. If the CLI version's permission syntax differs from `,read_items`, follow `--help` — the requirement is read-only on the single vault. Save the token output for the next step.

- [ ] **Step 3: Generate the access-key encryption key and create the 1Password item**

```bash
op item create --vault lab --category "Secure Note" --title semaphore \
  "admin-password[password]=$(openssl rand -base64 24)" \
  "access-key-encryption[password]=$(head -c32 /dev/urandom | base64)" \
  "connect-token[password]=<TOKEN-FROM-STEP-2>" \
  "oidc-client-id[text]=<CLIENT-ID-FROM-STEP-1>" \
  "oidc-client-secret[password]=<CLIENT-SECRET-FROM-STEP-1>"
```

- [ ] **Step 4: Create the GitHub deploy key (read-only) on homelab-automation**

```bash
ssh-keygen -t ed25519 -N '' -C 'semaphore@lab' \
  -f /private/tmp/claude-501/-Users-colinbruner-code-colinbruner-homelab-k8s/87b6c60e-be26-4202-9714-66bdfb8ca44a/scratchpad/semaphore-deploy-key
gh repo deploy-key add /private/tmp/claude-501/-Users-colinbruner-code-colinbruner-homelab-k8s/87b6c60e-be26-4202-9714-66bdfb8ca44a/scratchpad/semaphore-deploy-key.pub \
  --repo colinbruner/homelab-automation --title semaphore
op item create --vault lab --category "Secure Note" --title semaphore-github-deploy \
  "private-key[password]=$(cat /private/tmp/claude-501/-Users-colinbruner-code-colinbruner-homelab-k8s/87b6c60e-be26-4202-9714-66bdfb8ca44a/scratchpad/semaphore-deploy-key)"
trash /private/tmp/claude-501/-Users-colinbruner-code-colinbruner-homelab-k8s/87b6c60e-be26-4202-9714-66bdfb8ca44a/scratchpad/semaphore-deploy-key*
```

(Deploy keys are read-only by default — do not pass `--allow-write`.) This key is pasted into Semaphore's Key Store in Task 7; it is never mounted into the pod.

- [ ] **Step 5: Verify the target-host SSH key exists**

```bash
op read "op://lab/semaphore-ssh/private key" > /dev/null && echo OK
```

The runbook says this key already exists (its pubkey is distributed by the `lab_user` role). If missing, coordinate with the homelab-automation session before continuing — do not invent a key here.

---

### Task 3: App manifests — `k8s/apps/semaphore/`

**Files:**
- Create: `k8s/apps/semaphore/namespace.yaml`
- Create: `k8s/apps/semaphore/resources/onepassword-semaphore.yaml`
- Create: `k8s/apps/semaphore/resources/pvc.yaml`
- Create: `k8s/apps/semaphore/resources/deployment.yaml`
- Create: `k8s/apps/semaphore/resources/service.yaml`
- Create: `k8s/apps/semaphore/resources/httproute.yaml`
- Create: `k8s/apps/semaphore/kustomization.yaml`
- Create: `k8s/apps/semaphore/README.md`

**Interfaces:**
- Consumes: 1Password item `vaults/lab/items/semaphore` (Task 2 field labels); StorageClass `nfs-csi-buckets` (exists, `k8s/platform/csi-nfs/resources/sc-buckets.yaml`); Connect service `onepassword-connect.1password.svc.cluster.local:8080`.
- Produces: Service `semaphore` port 3000 in namespace `semaphore`; HTTPRoute expecting Gateway listener cert `semaphore-tls` (Task 4). The apps ApplicationSet discovers the directory automatically — no ArgoCD wiring needed.

- [ ] **Step 1: Create the working branch**

```bash
git -C /Users/colinbruner/code/colinbruner/homelab-k8s checkout main && git pull && git checkout -b feat/semaphore
```

- [ ] **Step 2: Write `k8s/apps/semaphore/namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: semaphore
```

- [ ] **Step 3: Write `k8s/apps/semaphore/resources/onepassword-semaphore.yaml`**

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: semaphore
spec:
  itemPath: "vaults/lab/items/semaphore"
```

The operator creates Secret `semaphore` whose keys are the item's field labels (`admin-password`, `access-key-encryption`, `connect-token`, `oidc-client-id`, `oidc-client-secret`).

- [ ] **Step 4: Write `k8s/apps/semaphore/resources/pvc.yaml`**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: semaphore-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-csi-buckets
  resources:
    requests:
      storage: 2Gi
```

- [ ] **Step 5: Write `k8s/apps/semaphore/resources/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: semaphore
  namespace: semaphore
  labels:
    app: semaphore
spec:
  replicas: 1
  strategy:
    type: Recreate # BoltDB is single-writer; never run two pods against the PVC
  selector:
    matchLabels:
      app: semaphore
  template:
    metadata:
      labels:
        app: semaphore
    spec:
      securityContext:
        fsGroup: 1001
      containers:
      - name: semaphore
        image: semaphoreui/semaphore:v2.18.20
        ports:
        - name: web
          containerPort: 3000
          protocol: TCP
        env:
        - name: SEMAPHORE_DB_DIALECT
          value: bolt
        - name: SEMAPHORE_WEB_ROOT
          value: https://semaphore.colinbruner.com
        - name: SEMAPHORE_ADMIN
          value: admin
        - name: SEMAPHORE_ADMIN_NAME
          value: Colin
        - name: SEMAPHORE_ADMIN_EMAIL
          value: admin@colinbruner.com
        - name: SEMAPHORE_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: semaphore
              key: admin-password
        - name: SEMAPHORE_ACCESS_KEY_ENCRYPTION
          valueFrom:
            secretKeyRef:
              name: semaphore
              key: access-key-encryption
        # Inherited by playbook runs so community.general.onepassword
        # lookups in group_vars/ resolve against in-cluster Connect.
        - name: OP_CONNECT_HOST
          value: http://onepassword-connect.1password.svc.cluster.local:8080
        - name: OP_CONNECT_TOKEN
          valueFrom:
            secretKeyRef:
              name: semaphore
              key: connect-token
        - name: SEMAPHORE_OIDC_PROVIDERS
          value: >-
            {"pocket-id": {"display_name": "Pocket ID",
            "provider_url": "https://auth.colinbruner.com",
            "client_id_file": "/etc/semaphore/oidc/client-id",
            "client_secret_file": "/etc/semaphore/oidc/client-secret",
            "redirect_url": "https://semaphore.colinbruner.com/api/auth/oidc/pocket-id/redirect",
            "scopes": ["openid", "profile", "email"],
            "username_claim": "preferred_username",
            "email_claim": "email",
            "name_claim": "name"}}
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /api/ping
            port: web
          initialDelaySeconds: 15
          periodSeconds: 15
        readinessProbe:
          httpGet:
            path: /api/ping
            port: web
          initialDelaySeconds: 5
          periodSeconds: 10
        volumeMounts:
        - name: data
          mountPath: /var/lib/semaphore
        - name: oidc
          mountPath: /etc/semaphore/oidc
          readOnly: true
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: semaphore-data
      - name: oidc
        secret:
          secretName: semaphore
          items:
          - key: oidc-client-id
            path: client-id
          - key: oidc-client-secret
            path: client-secret
```

- [ ] **Step 6: Write `k8s/apps/semaphore/resources/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: semaphore
  namespace: semaphore
  labels:
    app: semaphore
spec:
  selector:
    app: semaphore
  ports:
  - name: web
    port: 3000
    targetPort: web
    protocol: TCP
```

- [ ] **Step 7: Write `k8s/apps/semaphore/resources/httproute.yaml`**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: semaphore
  namespace: semaphore
spec:
  parentRefs:
  - name: shared-gateway
    namespace: gateway
    sectionName: https
  hostnames:
  - semaphore.colinbruner.com
  - semaphore-internal.colinbruner.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: semaphore
      port: 3000
```

- [ ] **Step 8: Write `k8s/apps/semaphore/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: semaphore

resources:
  - namespace.yaml
  - resources/onepassword-semaphore.yaml
  - resources/pvc.yaml
  - resources/deployment.yaml
  - resources/service.yaml
  - resources/httproute.yaml
```

- [ ] **Step 9: Write `k8s/apps/semaphore/README.md`**

```markdown
# Semaphore

[Semaphore UI](https://semaphoreui.com/) runs `colinbruner/homelab-automation`
Ansible playbooks on a schedule (weekly `site.yml` apply, Sun 04:00).

- **Canonical runbook**: `docs/semaphore.md` in homelab-automation — read it
  before changing schedules or templates. Ops playbooks are never scheduled.
- **State**: BoltDB on the `semaphore-data` PVC (`nfs-csi-buckets`). Single
  replica, `Recreate` strategy — BoltDB is single-writer.
- **Secrets**: `OnePasswordItem` -> Secret `semaphore`
  (`op://lab/semaphore`). The pod's `OP_CONNECT_TOKEN` is read-only on the
  `lab` vault; playbook runs inherit `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` for
  `community.general.onepassword` lookups.
- **Auth**: local `admin` (bootstrap) + Pocket ID OIDC
  (`https://auth.colinbruner.com`). OIDC users are non-admin by default.
- **URLs**: https://semaphore.colinbruner.com (tunnel),
  https://semaphore-internal.colinbruner.com (LAN).
- **In-UI config** (Key Store, repository, environment, task templates,
  schedules, notifications) is manual — see the runbook.
```

- [ ] **Step 10: Validate the rendered app (this is the test)**

```bash
cd /Users/colinbruner/code/colinbruner/homelab-k8s
kustomize build --enable-helm k8s/apps/semaphore \
  | kubeconform -strict -ignore-missing-schemas \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

Expected: exit 0, no errors. Also eyeball the rendered output once: `kustomize build --enable-helm k8s/apps/semaphore | less` — confirm every resource landed in namespace `semaphore` and the OIDC JSON survived YAML folding as one line.

- [ ] **Step 11: Commit**

```bash
git add k8s/apps/semaphore
git commit -m "feat: add semaphore app for scheduled ansible applies"
```

---

### Task 4: Gateway wiring — certificate + listener

**Files:**
- Create: `k8s/platform/gateway/certificates/semaphore.yaml`
- Modify: `k8s/platform/gateway/gateway.yaml` (https listener `certificateRefs`, after `dashboard-tls`)
- Modify: `k8s/platform/gateway/kustomization.yaml` (add cert to resources)

**Interfaces:**
- Consumes: ClusterIssuer `letsencrypt-prod`; Gateway `shared-gateway`.
- Produces: Secret `semaphore-tls` in namespace `gateway`, referenced by the shared https listener; serves the HTTPRoute from Task 3.

- [ ] **Step 1: Write `k8s/platform/gateway/certificates/semaphore.yaml`**

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: semaphore-tls
  namespace: gateway
spec:
  secretName: semaphore-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - semaphore.colinbruner.com
  - semaphore-internal.colinbruner.com
```

- [ ] **Step 2: Add the certificateRef to `k8s/platform/gateway/gateway.yaml`**

In the `https` listener's `tls.certificateRefs` list, after the `dashboard-tls` entry, add:

```yaml
      - kind: Secret
        name: semaphore-tls
```

- [ ] **Step 3: Add the certificate to `k8s/platform/gateway/kustomization.yaml`**

Add `certificates/semaphore.yaml` to the `resources:` list, next to the existing `certificates/argocd.yaml` / `certificates/dashboard.yaml` entries (match the file's existing ordering style).

- [ ] **Step 4: Validate the rendered platform component**

```bash
kustomize build --enable-helm k8s/platform/gateway \
  | kubeconform -strict -ignore-missing-schemas \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add k8s/platform/gateway
git commit -m "feat: add semaphore TLS cert to shared gateway"
```

---

### Task 5: PR, DNS, and deploy verification

**Files:** none in this repo (DNS lives in the external Terraform Cloudflare config; public CNAME via cloudflared CLI).

**Interfaces:**
- Consumes: everything above; ArgoCD apps ApplicationSet auto-creates the `semaphore` Application on merge.
- Produces: a running, reachable Semaphore at both hostnames; gate for Task 6.

- [ ] **Step 1: Push and open the PR**

```bash
git push -u origin feat/semaphore
gh pr create --title "feat: deploy Semaphore UI for scheduled Ansible applies" \
  --body "$(cat <<'EOF'
Deploys Semaphore UI (BoltDB on NFS PVC, Pocket ID OIDC, 1Password Connect env)
per homelab-automation docs/semaphore.md. Adds semaphore-tls to the shared
gateway. In-UI configuration follows post-merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Wait for CI (kustomize/kubeconform/yamllint) to pass, then merge.

- [ ] **Step 2: Internal DNS — Terraform (outside this repo)**

Add `semaphore-internal.colinbruner.com` A record → MetalLB Gateway IP in the Terraform Cloudflare config and apply, following the same pattern as `dashboard-internal`.

- [ ] **Step 3: Public DNS — tunnel route**

```bash
cloudflared tunnel route dns homelab semaphore.colinbruner.com
```

(The cloudflared ConfigMap's `*.colinbruner.com` wildcard rule already routes it to Envoy Gateway — no manifest change.)

- [ ] **Step 4: Watch ArgoCD converge and verify the workload**

```bash
kubectl -n argocd get application semaphore
kubectl -n semaphore get pods,pvc,secret,httproute
kubectl -n gateway get certificate semaphore-tls
```

Expected: Application Synced/Healthy; pod Running 1/1; PVC Bound; Secret `semaphore` present with 5 keys; certificate Ready=True. If the pod crash-loops on DB open, check volume permissions (`fsGroup: 1001` is set; the image runs as uid 1001) and describe the pod before changing anything.

- [ ] **Step 5: Verify both URLs and both login paths**

```bash
curl -s https://semaphore.colinbruner.com/api/ping
curl -s https://semaphore-internal.colinbruner.com/api/ping
```

Expected: `pong` from both. In a browser: log in as `admin` with `op read "op://lab/semaphore/admin-password"`, log out, then log in via the Pocket ID button (redirects to auth.colinbruner.com and back).

- [ ] **Step 6: Promote your OIDC user to admin**

OIDC users are non-admin by default. After the first Pocket ID login, promote it from inside the pod:

```bash
kubectl -n semaphore exec deploy/semaphore -- \
  semaphore user change-by-login --admin --login <your-pocket-id-username>
```

---

### Task 6: In-Semaphore configuration (manual, per runbook)

All in the Semaphore UI. The runbook table in `docs/semaphore.md` is authoritative — re-read it first.

**Files:** none

**Interfaces:**
- Consumes: `op://lab/semaphore-ssh/private key` (target hosts), `op://lab/semaphore-github-deploy/private-key` (repo clone), pod env `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN`.
- Produces: a scheduled weekly apply of `site.yml`; manual templates for everything else.

- [ ] **Step 1: Key Store** — add SSH key `semaphore` (paste `op read "op://lab/semaphore-ssh/private key"`) and SSH key `github-deploy` (paste `op read "op://lab/semaphore-github-deploy/private-key"`).

- [ ] **Step 2: Repository** — `git@github.com:colinbruner/homelab-automation.git`, branch `main`, auth `github-deploy`. Set the project's playbook path so tasks run from `ansible/` (Semaphore auto-installs `requirements.yml` collections).

- [ ] **Step 3: Environment** — create environment `lab` exposing `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` to task runs, matching the pod values (read the token with `op read "op://lab/semaphore/connect-token"`).

- [ ] **Step 4: Task templates** — one per playbook, exactly per the runbook table:

| Template | Playbook | Schedule |
|---|---|---|
| site | `playbooks/site.yml` | `0 4 * * 0` (Sun 04:00) |
| site (check) | `playbooks/site.yml` with `--check --diff` | `0 4 * * 3` (Wed 04:00, delete after ~1 month of clean runs) |
| dns-lb | `playbooks/dns-lb.yml` | none (manual) |
| pxe | `playbooks/pxe.yml` | none (manual) |
| warp-connector | `playbooks/warp-connector.yml` | none (manual) |
| proxmox | `playbooks/proxmox.yml` | none (manual) |
| ops: capacity-report | `playbooks/ops/capacity-report.yml` | **never** |
| ops: provision-worker | `playbooks/ops/provision-worker.yml` | **never** |
| ops: download-talos | `playbooks/ops/download-talos.yml` | **never** |

- [ ] **Step 5: Notifications** — configure an alert integration so **failed tasks** notify (channel is still TBD per the runbook — pick one and note it back in `docs/semaphore.md`).

- [ ] **Step 6: Smoke-run** — manually run the `dns-lb` template with `--check --diff` first. Expected: clone succeeds via deploy key, collections install, 1Password lookups resolve (proves `OP_CONNECT_*` + read-only token), SSH to targets works (proves Key Store key + egress), check-mode diff is empty or plausible. Then run `site (check)` once manually before trusting the schedules.

- [ ] **Step 7: Close the loop** — once schedules are live, remember: **merging to homelab-automation `main` is a deploy** (applied within the week, no human in the loop). Update `docs/semaphore.md` status section in homelab-automation to reflect "deployed".
