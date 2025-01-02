# Grafana Labs

The subdirectores within this monitoring directory serve the following purpose:
- operator: installs and configure grafana/prometheus operators.
- manifests: contains manfiests for deploying, configuring, and managing grafana/prometheus.

## Prerequisites

Install jb and gojsontoyaml, also need jsonnet.. `brew install jsonnet`
```bash
go install -a github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest
go install -a github.com/brancz/gojsontoyaml@latest
```

## Install Operators
Operators are cluster scoped and installed in the default namespace. This organizes monitoring operators into a single 'default' namespace and allows for targeted namespace deployments of the actual applications.

Before installing, we need to create the monitoring namespace and initial secrets.
```bash
# Creates k8s namespace 'monitoring' for the following operators and pods to be deployed
$ kubectl apply -f manifests/namespace.yaml && kubens monitoring
# Creates Grafana app admin username/password as k8s secrets synced from 1Password
$ kubectl apply -f manifests/1password.yaml
```

### Grafana Operator
Running the following script will install the Grafana operator within the `default` namespace.
```bash
$ ./operator/install-grafana.sh
```
https://grafana.github.io/grafana-operator/docs/installation/helm/

### Prometheus Operator
Running the following script will install the Prometheus operator within the `default` namespace.
```bash
$ ./operator/install-prometheus.sh
```
For more information on this script please view the [operator/build/README.md](./operator/build/README.md)

## Configuring Monitoring Cluster
While we get a lot "for free" from the initial setup of Grafana and Prometheus operators, we still want to configure the cluster a bit further.
```bash
# Switch namespace to monitoring
$ kubens monitoring

###
# Configure Prometheus
###
$ kubectl apply -f manifests/prometheus-ingress.yaml
$ kubectl apply -f manifests/prometheus-scrape.yaml

###
# Configure Grafana
###
$ kubectl apply -f manifests/grafana.yaml
$ kubectl apply -f manifests/grafana-ingress.yaml
$ kubectl apply -f manifests/grafana-datasource.yaml
$ kubectl apply -f manifests/grafana-dashboard.yaml
```

## Dashboards
- https://github.com/DevOps-Nirvana/Grafana-Dashboards
