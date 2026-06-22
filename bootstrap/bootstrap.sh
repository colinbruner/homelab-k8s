#!/usr/bin/env bash
set -euo pipefail

SCRIPTPATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

###############################################################################
# Cleanup trap — remove temp credentials file on exit
###############################################################################
CREDENTIALS_FILE=""
cleanup() {
  if [[ -n "${CREDENTIALS_FILE}" && -f "${CREDENTIALS_FILE}" ]]; then
    rm -f "${CREDENTIALS_FILE}"
  fi
}
trap cleanup EXIT

###############################################################################
# Step 1: 1Password root secrets (the single manual root-of-trust)
###############################################################################
echo "[INFO]: Step 1 — Ensuring 1Password root secrets..."

# Create namespace if absent
if ! kubectl get namespace 1password >/dev/null 2>&1; then
  echo "[INFO]: Creating 1password namespace..."
  kubectl apply -f "${SCRIPTPATH}/../k8s/platform/1password/namespace.yaml"
else
  echo "[INFO]: 1password namespace already exists."
fi

# Create op-credentials secret if absent
if ! kubectl get secret op-credentials -n 1password >/dev/null 2>&1; then
  echo "[INFO]: Creating op-credentials secret..."
  CREDENTIALS_FILE="$(mktemp)"
  op document get --vault homelab "1Password Operator Creds" --out-file "${CREDENTIALS_FILE}"
  kubectl create secret generic op-credentials \
    --namespace 1password \
    --from-file="1password-credentials.json=${CREDENTIALS_FILE}"
  rm -f "${CREDENTIALS_FILE}"
  CREDENTIALS_FILE=""
else
  echo "[INFO]: op-credentials secret already exists. Skipping."
fi

# Create op-connect-token secret if absent.
# The token is piped via stdin so it never appears in any process's argv.
if ! kubectl get secret op-connect-token -n 1password >/dev/null 2>&1; then
  echo "[INFO]: Creating op-connect-token secret..."
  op read "op://homelab/1Password Operator Creds/op connect token" \
    | kubectl create secret generic op-connect-token \
        --namespace 1password \
        --from-file="token=/dev/stdin" \
        --dry-run=client -o yaml \
    | kubectl apply -f -
else
  echo "[INFO]: op-connect-token secret already exists. Skipping."
fi

###############################################################################
# Step 2: Install ArgoCD
###############################################################################
echo "[INFO]: Step 2 — Installing ArgoCD..."

if ! kubectl get namespace argocd >/dev/null 2>&1; then
  echo "[INFO]: Building and applying ArgoCD manifests..."
  kustomize build --enable-helm "${SCRIPTPATH}/argocd" | kubectl apply --server-side --force-conflicts -f -
  echo "[INFO]: Waiting for ArgoCD repo-server rollout..."
  kubectl -n argocd rollout status deploy/argo-cd-argocd-repo-server --timeout=300s
  echo "[INFO]: Waiting for ArgoCD server rollout..."
  kubectl -n argocd rollout status deploy/argo-cd-argocd-server --timeout=300s
  echo "[INFO]: ArgoCD is ready."
else
  echo "[INFO]: argocd namespace already exists. Skipping ArgoCD install."
fi

###############################################################################
# Step 3: Apply the GitOps root (ApplicationSets + cronhealth)
###############################################################################
echo "[INFO]: Step 3 — Applying GitOps root ApplicationSets..."
kubectl apply -k "${SCRIPTPATH}/root"

echo "[INFO]: Bootstrap complete. ArgoCD will converge all remaining resources."
