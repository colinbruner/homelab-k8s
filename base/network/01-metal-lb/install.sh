#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="metallb-system"

function install_metal_lb() {
    kustomize build $SCRIPTPATH | kfilt -i kind=CustomResourceDefinition | kubectl apply -f -
    kustomize build $SCRIPTPATH | kfilt -i kind=CustomResourceDefinition | kubectl wait --for condition=established --timeout=60s -f -
    kustomize build $SCRIPTPATH | kubectl apply -f -
}

if [[ $(kubens | grep $NAMESPACE) != $NAMESPACE ]]; then
    echo "[INFO]: Installing Metal LB.."
    install_metal_lb
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi
