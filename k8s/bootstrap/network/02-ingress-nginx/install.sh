#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="ingress-nginx"

function install_ingress_nginx() {
    kustomize build --enable-helm $SCRIPTPATH | kubectl apply -f -
}

if [[ $(kubens | grep $NAMESPACE) != $NAMESPACE ]]; then
    echo "[INFO]: Installing Ingress NGINX.."
    install_ingress_nginx
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi
