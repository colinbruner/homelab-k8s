# Monitoring

Bootstrap installs the monitoring **operators only**:

- **Prometheus**: `prometheus/install.sh` builds manifests from Jsonnet and installs Prometheus Operator CRDs + core components. Custom resources (ScrapeConfig, ServiceMonitor) are also applied here as they are tightly coupled to the operator install.

All application-level resources (Grafana Operator, Grafana CR, secrets, HTTPRoutes, dashboards, datasources) are managed by ArgoCD via `k8s/namespaces/monitoring/`.

## Install

The installation process is handled through [bootstrap.sh](../bootstrap.sh), but can be individually run by `install.sh` script in any sub-directory.

## Dashboards

- https://github.com/DevOps-Nirvana/Grafana-Dashboards
