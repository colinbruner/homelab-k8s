# Network

Install network infrastructure components. Each directory has an `install.sh` that captures the necessary logic required to install the specific application.

Bootstrap installs **operators, CRDs, and Helm charts only**. All application-level resources (Gateway, Certificates, HTTPRoutes) are managed by ArgoCD via `k8s/namespaces/`.

## Components

1. **01-metal-lb/** — MetalLB load balancer (Helm chart + IP pool + L2 advertisement)
2. **02-gateway/** — Envoy Gateway controller (Gateway API CRDs + Helm chart + GatewayClass). The Gateway resource, TLS Certificates, and HTTP redirect are managed by ArgoCD in `k8s/namespaces/gateway-system/`.
3. **03-cert-manager/** — cert-manager (Helm chart + ClusterIssuers)

## Note

Kustomize was considered for orchestrating the full install, however due to cert-manager taking some time to create CRDs, utilizing Kustomize by itself is not possible without error. Each component's `install.sh` handles ordering and wait conditions.
