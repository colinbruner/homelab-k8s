# Homelab-k8s

The following files are used to deploy resources onto my homelab kubernetes cluster. Mostly used as a lab for experimenting with new/interesting technology.

I'm trying to work out the directory structure a bit, so this is all likely to change frequently as I develop a framework.

## Design

The goal is to bootstrap the "base services" manually, plus ArgoCD, then configure everything within ArgoCD to be deployed and managed through CD.

There are two major components [base](./base) and [apps](./apps).

- base: these are the cluster level components required.
- apps: this is essentially everything else, base components support these.

![Homelab Dependencies](./assets/dependencies.png)

## Bootstrapping

Running [boopstrap.sh](./boostrap.sh) will execute all `install.sh` scripts within the `base` directory.

These scripts are intended to be idemponent and only make changes when their target namespace does NOT exist.

```bash
# Expects the following:
# - Kube context @ desired cluster to bootstrap with appropriate access
# - kubectl, kustomize, kfilt, installed and within PATH.
./bootstrap.sh
```

## Services

For more information about the `base` services installed, view [base/README.md](./base/README.md).
