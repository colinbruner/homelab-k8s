#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
HELM_CHART_VERSION="v5.15.1"

function install_grafana() {
    helm upgrade -i grafana-operator \
        --version $HELM_CHART_VERSION \
        oci://ghcr.io/grafana/helm-charts/grafana-operator

    kustomize build $SCRIPTPATH | kubectl apply -f -
}

if [[ -z $(kubectl get crds | grep "grafana") ]]; then
    echo "[INFO]: Installing Grafana.."
    install_grafana
else
    echo "[INFO]: Grafana CRDs already exists. Continuing.."
fi
