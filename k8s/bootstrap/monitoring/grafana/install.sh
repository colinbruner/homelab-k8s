#!/bin/bash -e

HELM_CHART_VERSION="v5.15.1"

function install_grafana() {
    helm upgrade -i grafana-operator \
        --namespace "monitoring" \
        --version $HELM_CHART_VERSION \
        oci://ghcr.io/grafana/helm-charts/grafana-operator

    # Grafana CR, secrets, and HTTPRoute are managed by ArgoCD
    # via k8s/namespaces/monitoring/.
}

if [[ -z $(kubectl get crds | grep "grafana") ]]; then
    echo "[INFO]: Installing Grafana Operator.."
    install_grafana
else
    echo "[INFO]: Grafana CRDs already exists. Continuing.."
fi
