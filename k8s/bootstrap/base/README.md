# Bootstrap

The following are organized as cluster wide "base" or "essential" services for cluster automation and operation.

## Base

### Secrets

- 1password: secret injection in native k8s secrets

### Network

- metal-lb: automatic DHCP binding to load balancer object for ingress
- ingress-nginx: ingress class for NGINX proxies, this handles routing requests to applications
- cert-manager: provides TLS certificates through a DNS challenge by LetsEncrypt

### Infra

- crossplane: for adding DNS records in Cloudflare for coordination with cert-manager

## CICD

- argocd: is used to installed all other applications outside of base, as well as manage those applications within base
- argowf: used for running jobs, workflows, crons, etc.

## Monitoring

Grafana Prometheus for easy monitoring dashboards and metrics scraping.

- grafana: install grafana-operator
- prometheus: install prometheus-operator, this is a bit more custom (jsonnet)
