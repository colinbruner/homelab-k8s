#!/bin/bash

# Need to install CRDs before, wait for CRDS to be ready via kubectl, then install rest.
# https://github.com/kubernetes/kubectl/issues/1117
# NOTE: unfortunately, the "solution" above is not possible as Kustomize does not like two yamls from same URL

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="cert-manager"
CERT_MANAGER_VERSION="v1.16.2"

function install_cert_manager() {
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm install \
      cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --version v1.16.2 \
      --set crds.enabled=true

    # Install CRDs
    #curl -sS -O https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml
    #kubectl apply -f cert-manager.crds.yaml
    #kubectl wait --for condition=established --timeout=60s -f cert-manager.crds.yaml
    #rm -f cert-manager.crds.yaml

    ## Install cert-manager
    #kustctl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml

    # Instal custom resources
    kustomize build $SCRIPTPATH | kubectl apply -f -
}

if [[ $(kubens | grep $NAMESPACE) != $NAMESPACE ]]; then
    echo "[INFO]: Installing Cert Manager.."
    install_cert_manager
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi
