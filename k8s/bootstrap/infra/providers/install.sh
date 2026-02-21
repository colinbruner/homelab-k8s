#!/bin/bash -e

# Install 'base' providers, currently only 'http'

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="crossplane-system"

function install_http_provider() {
    pushd $SCRIPTPATH/http >/dev/null
    ./generate.sh
    kustomize build . | kubectl apply -f -
    popd >/dev/null

}

# base providers
function install_providers {
    provider_http_status=$(kubectl get providers \
        -n $NAMESPACE \
        -o yaml | \
        yq '.items[] | select(.metadata.name == "provider-http") | .status.conditions[] | select(.type == "Installed") | .status' \
    )
    if [[ $provider_http_status != "True" ]]; then
        echo "[INFO]: Installing Crossplane Provider 'http'.."
        install_http_provider
    else
        echo "[INFO]: 'http' Provider already installed. Continuing.."
    fi
}

# Wait for Crossplane to be installed before beginning providers..
kubectl -n $NAMESPACE wait --for condition=established --timeout=60s crd/providers.pkg.crossplane.io >/dev/null

echo "[INFO]: Installing Crossplane Providers.."
install_providers
echo "[INFO]: Crossplane Providers installed successfully."
