# Homelab-k8s

The following files are used to deploy resources onto my homelab kubernetes cluster. Mostly used as a lab for experimenting with new/interesting technology.

I'm trying to work out the directory structure a bit, so this is all likely to change frequently as I develop a framework.

## Design

The goal is to bootstrap the "base services" manually, plus ArgoCD, then configure everything within ArgoCD to be deployed and managed through CD.

There are two major components [base](./base) and [apps](./apps).

- base: these are the cluster level components required.
- apps: this is essentially everything else, base components support these.

## Bootstrapping

Running [boopstrap.sh](./boostrap.sh) will execute all `install.sh` scripts within the `base` directory.

These scripts are intended to be idemponent and only make changes when their target namespace does NOT exist.

```bash
# Expects the following:
# - Kube context @ desired cluster to bootstrap with appropriate access
# - kubectl, kustomize, kfilt, installed and within PATH.
./bootstrap.sh
```

### Base Services:

#### Secrets

- 1password: secret injection in native k8s secrets

#### Network

- metal-lb: automatic DHCP binding to load balancer object for ingress
- ingress-nginx: ingress class for NGINX proxies, this handles routing requests to applications
- cert-manager: provides TLS certificates through a DNS challenge by LetsEncrypt

#### Infra

- crossplane: for adding DNS records in Cloudflare for coordination with cert-manager

#### Monitoring

Grafana Prometheus for easy monitoring dashboards and metrics scraping.

- grafana: install grafana-operator
- prometheus: install prometheus-operator, this is a bit more custom (jsonnet)

#### Argo

- argocd: is used to installed all other applications outside of base, as well as manage those applications within base
- argowf: used for running jobs, workflows, crons, etc.
