# Monitoring

Due to Grafana and Prometheus being rather tightly coupled AND installed into same generic `monitoring` namespace, this structure is slightly different with a single `namespace.yaml` manifest within the root of the [monitoring](./) directory.

## Install

The installation process is handled through [bootstrap.sh](../bootstrap.sh), but can be individually run by `install.sh` script in any sub-directory.

The `install.sh` script is intended only for initial installation (bootstrapping). ArgoCD should manage subsequent changes.

## Dashboards

- https://github.com/DevOps-Nirvana/Grafana-Dashboards
