# k8s/bootstrap

One-time cluster bootstrapping. Installs operators, controllers, and CRDs only.

**Everything else** (application config, HTTPRoutes, Certificates, DNS records, etc.) lives in
`k8s/namespaces/` and is managed declaratively by ArgoCD.

---

## When to Use Bootstrap

Bootstrap is for the **chicken-and-egg** problem: resources that must exist before ArgoCD
can manage anything. Run it once on a fresh cluster, then let ArgoCD take over.

Do **not** add application-level resources here. If ArgoCD can manage it, it should.

---

## Running Bootstrap

```bash
cd k8s/bootstrap/
./bootstrap.sh
```

The script is idempotent — safe to re-run. Each component checks whether it is already
installed before applying anything.

---

## Bootstrap Order

Components are installed in dependency order:

```
1. secrets/       — Secret management operators (must run before anything needs secrets)
2. network/       — Load balancer → Gateway → Cert-manager (each depends on the prior)
3. infra/         — Crossplane engine (must run before ArgoCD can apply Provider CRs)
4. argocd/        — ArgoCD itself (takes over all subsequent management)
5. monitoring/    — Prometheus operator + stack (CRDs needed before ServiceMonitor CRs work)
```

---

## Components

### `secrets/`

| Component | Installs | ArgoCD manages |
|-----------|----------|----------------|
| `1password/` | 1Password Operator + Connect | OnePasswordItem CRs (per namespace) |

### `network/`

| Component | Installs | ArgoCD manages |
|-----------|----------|----------------|
| `01-metal-lb/` | MetalLB controller + CRDs | `IPAddressPool`, `L2Advertisement` → `k8s/namespaces/metallb-system/` |
| `02-gateway/` | Envoy Gateway + Gateway API CRDs + `GatewayClass` | `Gateway`, `HTTPRoute`, `Certificate` → `k8s/namespaces/gateway-system/` |
| `03-cert-manager/` | cert-manager Helm chart + CRDs | `ClusterIssuer` → `k8s/namespaces/cert-manager/` |

### `infra/`

| Component | Installs | ArgoCD manages |
|-----------|----------|----------------|
| `crossplane/` | Crossplane engine + CRDs | — |
| `providers/` | Waits for Crossplane CRDs; signals readiness | `Provider`, `ProviderConfig` → `k8s/namespaces/crossplane-system/` |

### `argocd/`

| Component | Installs | ArgoCD manages |
|-----------|----------|----------------|
| `argocd/` | ArgoCD Helm chart (server, controller, repo-server, applicationset, redis) | ArgoCD config, RBAC, `ApplicationSet`, `HTTPRoute` → `k8s/namespaces/argocd/` |

### `monitoring/`

| Component | Installs | ArgoCD manages |
|-----------|----------|----------------|
| `prometheus/` | prometheus-operator, Prometheus, Alertmanager, node-exporter, kube-state-metrics (via Jsonnet) | `ScrapeConfig`, `ServiceMonitor`, Grafana CR → `k8s/namespaces/monitoring/` |

---

## Prometheus Build (Jsonnet)

The Prometheus stack is built from [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)
Jsonnet sources rather than a Helm chart, to allow full control over the generated manifests.

```bash
cd monitoring/prometheus/build/

# Install Jsonnet dependencies (first time only)
jb install

# Rebuild manifests
jsonnet -J vendor -m manifests prometheus.jsonnet | \
  xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}
```

The `install.sh` handles this automatically and applies the results to the cluster.

---

## What Does NOT Belong Here

- `HTTPRoute`, `Certificate`, `Gateway` resources → `k8s/namespaces/gateway-system/`
- `ClusterIssuer` resources → `k8s/namespaces/cert-manager/`
- `IPAddressPool`, `L2Advertisement` → `k8s/namespaces/metallb-system/`
- Crossplane `Provider`, `ProviderConfig` → `k8s/namespaces/crossplane-system/`
- `ScrapeConfig`, `ServiceMonitor`, Grafana CRs → `k8s/namespaces/monitoring/`
- Any application-level resource for any user-facing service
