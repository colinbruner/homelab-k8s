#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="argocd"

function install_argo_cd() {
    kustomize build $SCRIPTPATH | kubectl apply -f -
}

if [[ ! $(kubens | grep $NAMESPACE) =~ $NAMESPACE ]]; then
    echo "[INFO]: Installing Argo CD.."
    install_argo_cd
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi
