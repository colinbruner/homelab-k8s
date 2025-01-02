# Ingress NGINX

Community version, based on NGINX Open Source, maintained by the Kubernetes community with a commitment from NGINX teams

- github: https://github.com/kubernetes/ingress-nginx
- docs: https://kubernetes.github.io/ingress-nginx/

## Kustomize (preferred)

```bash
kustomize build --enable-helm . | kubectl apply -f -
```

## Helm (legacy)

### Install

The following commands will install the NGINX Ingress controller via helm

```bash
$ helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

$ helm repo update

$ helm install ingress-nginx \
  ingress-nginx/ingress-nginx \
  --values values.yaml \
  --create-namespace \
  --namespace ingress-nginx
```

### Upgrade

The following upgrades and redeloys any configuration changes to ingress-nginx.

```bash
$ helm upgrade ingress-nginx \
  ingress-nginx/ingress-nginx \
  --values values.yaml
```
