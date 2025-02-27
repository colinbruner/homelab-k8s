#!/bin/bash -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

#function cleanup_secrets() {
#  unset OP_CONNECT_TOKEN
#  rm -f $CREDENTIALS_FILE
#}
#
#trap cleanup_secrets EXIT

function install_external_secrets() {
    # Add helm repo
    helm repo add external-secrets https://charts.external-secrets.io --force-update

    # Install CRDs
    kustomize build | kubectl apply -f -

    # Install Operator
    helm install external-secrets \
      external-secrets/external-secrets \
      -n external-secrets \
      --create-namespace \
      --set installCRDs=false

    # Wait until CRDS are ready
    kubectl wait --for condition=established --timeout=60s crds/secretstores.external-secrets.io
}

if [[ ! $(kubens | grep "external-secrets") == "external-secrets" ]]; then
    echo "[WARNING]: Implement Me"
    #echo "[INFO]: Installing External Secrets Operator.."
    #install_external_secrets
else
    echo "[INFO]: External Secrets namespace already exists. Continuing.."
fi
