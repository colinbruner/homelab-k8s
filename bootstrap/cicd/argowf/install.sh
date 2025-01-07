#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="argo"

function install_argo_wf() {
    kustomize build $SCRIPTPATH | kfilt -i kind=CustomResourceDefinition | kubectl apply -f -
    kustomize build $SCRIPTPATH | kfilt -i kind=CustomResourceDefinition | kubectl wait --for condition=established --timeout=60s -f -
    kustomize build $SCRIPTPATH | kubectl apply -f -
}

if [[ ! $(kubens | grep $NAMESPACE) =~ $NAMESPACE ]]; then
    echo "[INFO]: Installing Argo Workflows.."
    install_argo_wf
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi
