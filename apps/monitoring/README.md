# Monitoring

The subdirectores within this monitoring directory serve the following purpose:
- kustomize.yaml: installs and configure grafana/prometheus operators via helm
- resources: contains manfiests for deploying, configuring, and managing grafana/prometheus.

NOTE: The [prometheus](./prometheus) directory is retained for easy reference of a custom build setup. It is not actively used.

## Install
```bash
# Build Kustomize manifests and pass to kubectl through stdin
kustomize build --enable-helm . | kubectl apply -f -
```

## Dashboards
- https://github.com/DevOps-Nirvana/Grafana-Dashboards
