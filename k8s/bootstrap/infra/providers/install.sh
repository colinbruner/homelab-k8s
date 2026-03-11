#!/bin/bash -e

# Crossplane Provider (provider-http) and ProviderConfig (http-cloudflare) are
# managed by ArgoCD via k8s/namespaces/crossplane-system/.
#
# ArgoCD will apply them once Crossplane is running (bootstrapped by infra/crossplane/install.sh).

NAMESPACE="crossplane-system"

echo "[INFO]: Crossplane providers are managed by ArgoCD (k8s/namespaces/crossplane-system/)."
echo "[INFO]: Waiting for Crossplane CRDs so ArgoCD can sync provider resources.."
kubectl -n $NAMESPACE wait --for condition=established --timeout=60s crd/providers.pkg.crossplane.io >/dev/null
echo "[INFO]: Crossplane CRDs ready. ArgoCD will install providers on next sync."
