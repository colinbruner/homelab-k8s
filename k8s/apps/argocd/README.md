# ArgoCD

## User Creation

```bash
# Get initial admin secret
kubectl get secret argocd-initial-admin-secret -o yaml | yq ".data.password" | base64 -d
# Login to ArgoCD with default admin credentials
argocd login argocd.colinbruner.com
# Update password for 'colin' user account
argocd account update-password --account colin
# Generate token for 'crossplane' automation account
argocd account update-password --account colin
```
