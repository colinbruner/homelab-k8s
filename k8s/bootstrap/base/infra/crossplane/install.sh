#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="crossplane-system"

function install_crossplane() {
    kubectl apply -f namespace.yaml

    helm repo add crossplane-stable https://charts.crossplane.io/stable --force-update
    helm install crossplane \
        --namespace $NAMESPACE \
        crossplane-stable/crossplane 

    # TODO
    #kustomize build . | kubectl apply -f -
}

if [[ $(kubens | grep $NAMESPACE) != $NAMESPACE ]]; then
    echo "[INFO]: Installing Crossplane.."
    install_crossplane
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi


