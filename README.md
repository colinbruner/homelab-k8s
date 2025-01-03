# Homelab-k8s

The following files are used to deploy resources onto my homelab kubernetes cluster. Mostly used as a lab for experimenting with new/interesting technology.

I'm trying to work out the directory structure a bit, so this is all likely to change frequently as I develop a framework.

## Bootstrap

The goal is to bootstrap the "base services" manually, plus ArgoCD, then configure everything within ArgoCD to be deployed and managed through CD.

### Base Services:

- 1password: secret injection in native k8s secrets
- metal-lb: automatic DHCP binding to load balancer object for ingress
- ingress-nginx: ingress class for NGINX proxies, this handles routing requests to applications
- cert-manager: provides TLS certificates through a DNS challenge by LetsEncrypt

### Future Base:

Depending on how involved the setup is..

- crossplane: for adding DNS records in Cloudflare for coordination with cert-manager

### Process

## Components

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
