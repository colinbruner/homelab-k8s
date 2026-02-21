#!/bin/bash -e

ARGOCD_HOST="${ARGOCD_HOST:-argocd.colinbruner.com}"
ARGOCD_OPERATOR_ACCOUNT="colin"

# Retrieve initial admin password from cluster
echo "[INFO]: Retrieving initial admin password from cluster..."
ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d)

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "[ERROR]: Could not retrieve argocd-initial-admin-secret. Is ArgoCD running?"
  exit 1
fi

# Prompt for the operator account password
echo "[INFO]: Setting password for ArgoCD account '${ARGOCD_OPERATOR_ACCOUNT}'."
read -rsp "Enter new password for '${ARGOCD_OPERATOR_ACCOUNT}': " OPERATOR_PASSWORD
echo
read -rsp "Confirm password: " OPERATOR_PASSWORD_CONFIRM
echo

if [[ "$OPERATOR_PASSWORD" != "$OPERATOR_PASSWORD_CONFIRM" ]]; then
  echo "[ERROR]: Passwords do not match."
  exit 1
fi

if [[ -z "$OPERATOR_PASSWORD" ]]; then
  echo "[ERROR]: Password cannot be empty."
  exit 1
fi

# Temporarily re-enable admin account
echo "[INFO]: Temporarily enabling admin account..."
kubectl patch configmap argocd-cm -n argocd \
  --type merge -p '{"data":{"admin.enabled":"true"}}' >/dev/null

# Log in as admin via ingress
echo "[INFO]: Logging in to ArgoCD at '${ARGOCD_HOST}'..."
argocd login "$ARGOCD_HOST" \
  --grpc-web \
  --username admin \
  --password "$ADMIN_PASSWORD"

# Set the operator account password
echo "[INFO]: Setting password for '${ARGOCD_OPERATOR_ACCOUNT}'..."
argocd account update-password \
  --account "$ARGOCD_OPERATOR_ACCOUNT" \
  --current-password "$ADMIN_PASSWORD" \
  --new-password "$OPERATOR_PASSWORD"

# Re-disable admin account
echo "[INFO]: Disabling admin account..."
kubectl patch configmap argocd-cm -n argocd \
  --type merge -p '{"data":{"admin.enabled":"false"}}' >/dev/null

echo "[INFO]: Done. You can now log in as '${ARGOCD_OPERATOR_ACCOUNT}' at https://${ARGOCD_HOST}"
