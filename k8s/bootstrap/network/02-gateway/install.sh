#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
NAMESPACE="envoy-gateway-system"
EG_VERSION="v1.7.0"
GATEWAY_API_VERSION="v1.2.1"

function install_gateway() {
    # 1. Install Gateway API standard CRDs
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml
    kubectl wait --for condition=established --timeout=60s \
      crd/gateways.gateway.networking.k8s.io \
      crd/httproutes.gateway.networking.k8s.io \
      crd/gatewayclasses.gateway.networking.k8s.io

    # 2. Install Envoy Gateway controller via Helm
    helm install eg oci://docker.io/envoyproxy/gateway-helm \
      --version ${EG_VERSION} \
      --namespace ${NAMESPACE} \
      --create-namespace \
      -f ${SCRIPTPATH}/helm-values.yaml

    # 3. Wait for Envoy Gateway to be ready
    kubectl wait --timeout=5m -n ${NAMESPACE} \
      deployment/envoy-gateway --for=condition=Available

    # 4. Apply namespace + GatewayClass
    kustomize build ${SCRIPTPATH} | kubectl apply -f -

    # Gateway, Certificates, and HTTPRoutes are managed by ArgoCD
    # via k8s/namespaces/gateway-system/ and individual namespace directories.
}

if [[ $(kubens | grep ${NAMESPACE}) != ${NAMESPACE} ]]; then
    echo "[INFO]: Installing Envoy Gateway.."
    install_gateway
else
    echo "[INFO]: ${NAMESPACE} namespace already exists. Continuing.."
fi
