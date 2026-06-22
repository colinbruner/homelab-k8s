## Task 7 Report: platform/cert-manager + platform/gateway

### Status: COMPLETE

### Files Created

**k8s/platform/cert-manager/**
- `kustomization.yaml` — helmChart cert-manager v1.16.2 from https://charts.jetstack.io + 3 resources
- `values.yaml` — `crds.enabled: true`
- `letsencrypt-prod.yaml` — ClusterIssuer (verbatim from namespaces/cert-manager)
- `letsencrypt-staging.yaml` — ClusterIssuer (verbatim)
- `onepassword-cloudflare.yaml` — OnePasswordItem (verbatim)
- `README.md`

**k8s/platform/gateway/**
- `kustomization.yaml` — helmChart gateway-helm v1.7.0 OCI + Gateway API CRDs remote + 12 local resources
- `values.yaml` — `config.extensionApis.enableEnvoyPatchPolicy: true` (from legacy helm-values.yaml)
- `gatewayclass.yaml` — GatewayClass `envoy-gateway` (from bootstrap)
- `namespace.yaml` — Namespace `gateway-system` (from bootstrap)
- `namespace-envoy-gateway-system.yaml` — Namespace `envoy-gateway-system` (chart doesn't create it)
- `envoy-proxy.yaml` — EnvoyProxy `proxy-config` (verbatim from namespaces/gateway-system)
- `gateway.yaml` — Gateway `shared-gateway` (verbatim)
- `http-redirect.yaml` — HTTPRoute (verbatim)
- `certificates/argocd.yaml` — Certificate (verbatim)
- `certificates/dashboard.yaml` — Certificate (verbatim)
- `certificates/garage.yaml` — Certificate (verbatim)
- `certificates/grafana.yaml` — Certificate (verbatim)
- `certificates/n8n.yaml` — Certificate (verbatim)
- `certificates/prometheus.yaml` — Certificate (verbatim)
- `certificates/uptime.yaml` — Certificate (verbatim)
- `README.md`

### OCI Helm Chart Form

**Working form:**
```yaml
helmCharts:
  - name: gateway-helm
    repo: oci://docker.io/envoyproxy
    version: v1.7.0
    releaseName: eg
    namespace: envoy-gateway-system
    valuesFile: values.yaml
```
First attempt, worked immediately. `name: gateway-helm` + `repo: oci://docker.io/envoyproxy` is the correct split for kustomize OCI support.

### Gateway API CRD Remote Resource Form

**Failed:** `github.com/kubernetes-sigs/gateway-api/config/crd/standard?ref=v1.2.1`
- Error: that directory has no `kustomization.yaml` so kustomize cannot treat it as a kustomize remote base.

**Working form:**
```yaml
- https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```
Direct URL to the release YAML works as a kustomize remote resource.

### Verification Output

```
== k8s/platform/cert-manager ==
exit: 0
== k8s/platform/gateway ==
exit: 0
```

### Gateway Render Contents Confirmed

- Deployment: envoy-gateway controller (in envoy-gateway-system)
- GatewayClass: envoy-gateway
- Gateway: shared-gateway
- 7 Certificates: argocd-tls, dashboard-tls, garage-tls, grafana-tls, n8n-tls, prometheus-tls, uptime-tls
- HTTPRoute: http-redirect
- EnvoyProxy: proxy-config
- 5 Gateway API CRDs: gatewayclasses, gateways, grpcroutes, httproutes, referencegrants
- 2 Namespaces: gateway-system, envoy-gateway-system

### Namespacing

No top-level `namespace:` field in gateway kustomization. Chart resources get `envoy-gateway-system` via helmChart namespace. App CRs retain explicit `namespace: gateway-system` from their metadata. GatewayClass is cluster-scoped (no namespace).

### Blocking Concerns

None.
