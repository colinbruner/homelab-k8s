# Prometheus

Prometheus is deployed in two parts:
1. [install.sh](./install.sh) to install Prometheus CRDs and supporting components.
2. Kustomize via kustomization.yaml to install my custom defined resources.

# Building
The following documents how to build the Prometheus manifests, the install.sh script builds these but will not saw prerequisites.

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
