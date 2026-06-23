# Prometheus

Prometheus is deployed in two parts:
1. `install.sh` to install Prometheus CRDs, operator, and core components from Jsonnet.
2. `kustomization.yaml` to install custom resources (ScrapeConfig, ServiceMonitor).

The Prometheus HTTPRoute and other application-level config are managed by ArgoCD via `k8s/namespaces/monitoring/`.

# Building
The following documents how to build the Prometheus manifests, the install.sh script builds these but will not show prerequisites.

## Prerequisites

Install jb and gojsontoyaml, also need jsonnet.. `brew install jsonnet`
```bash
go install -a github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest
go install -a github.com/brancz/gojsontoyaml@latest
```

# Installing
To install the first part:
```bash
./install.sh
```

The second part can be installed after installation of CRDs installed in the first part:
```bash
kubectl apply -k .
```
