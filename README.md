# Homelab-k8s

The following files are used to deploy resources onto my homelab kubernetes cluster. Mostly used as a lab for experimenting with new/interesting technology.

I'm trying to work out the directory structure a bit, but for the time being we'll go with a high level categorization of components:

- 1password: cluster level secrets, this predicates pretty much everything else
- network: all cluster level components.. ingress, certificates
- cicd: Argo Workflows and (eventually) ArgoCD for managing Kubernetes resources
- infra: Crossplane.io to handle configuring Cloud Infrastructure with k8s
- monitoring: Grafana, Prometheus, Loki (eventually) for k8s cluster components
- apps: Any applications deployed within the Cluster (future)
  - Keycloak
  - Tailscale
  - etc

## Installing

This will likely be changing as I play around, but currently trying to group and control resources with Kustomize.

Installation at any directory level, including root:
```bash
kubectl kustomize --enable-helm . | kubectl apply -f -
```

> NOTE: Currently 1password installation is manual

## Monitoring

Grafana Prometheus for easy monitoring dashboards and metrics scraping.

- monitoring: contains installation logic for both.. this is a bit more custom (jsonnet)

## Argo

Install Argo Workflows, perhaps CD in the future?
