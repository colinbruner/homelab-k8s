# ArgoCD

https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/

## Bootstrap

This directory installs the ArgoCD Helm chart and creates the `argocd` namespace. That's it.

All ArgoCD configuration (users, RBAC, ApplicationSet, HTTPRoute) is managed by ArgoCD itself via `k8s/namespaces/argocd/`.
