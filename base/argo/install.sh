#!/bin/bash -ex

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="argo"

# TODO:
function install_argo_cd() {
    echo
}

function install_argo_wf() {
    kustomize build $SCRIPTPATH | kfilt -i kind=CustomResourceDefinition | kubectl apply -f -
    kustomize build $SCRIPTPATH | kfilt -i kind=CustomResourceDefinition | kubectl wait --for condition=established --timeout=60s -f -
    kustomize build $SCRIPTPATH | kubectl apply -f -
}

if [[ $(kubens | grep $NAMESPACE) != $NAMESPACE ]]; then
    install_argo_wf
    echo "[INFO]: Installing Argo Workflows.."
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi
