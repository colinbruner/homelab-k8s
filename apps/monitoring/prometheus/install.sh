#!/bin/bash -e

# Docs: https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md

###
# Helm
###
#PROM_CHART_VERSION=61.3.1
#
#helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#helm repo update
#helm install kube-prometheus \
#  --values ./values/prom.yaml \
#  prometheus-community/kube-prometheus-stack

###
# The below code clones 'kube-prometheus' and installs all components excluding 
# 'grafana', which is installed separately.

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

pushd $SCRIPTPATH/build >/dev/null

# Make sure to start with a clean 'manifests' dir
function setupManifests() {
  #rm -rf manifests
  mkdir -p manifests/setup
}

function setupVendors() {
  # hardcoded @mail
  if [[ ! -d vendor ]]; then
    jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@main
  else
    echo "vendor directory exists. Continuing..."
  fi
}

function jsonnetBuild() {
  # Calling gojsontoyaml is optional, but we would like to generate yaml, not json
  jsonnet -J vendor -m manifests "${1-example.jsonnet}" | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}
}

function createCRDs() {
  local crdSuffix='*CustomResourceDefinition.yaml'
  # separate CRDs from manifests
  mv manifests/${crdSuffix} manifests/setup

  set +e # allow non-zero return codes within loop
  # assumes root of build directory
  for file in manifests/setup/*.yaml; do
    local crdResource=$(yq ".metadata.name" $file)
    # check if crd exists
    kubectl get $crdResource &>/dev/null
    if [[ $? != 0 ]]; then
      kubectl create -f $file
    else
      echo "CRD: '$crdResource' already exists. Continuing..."
    fi
  done
  set -e # return to failing on non-zero return codes
}

function applyManifests() {
  local path=$1 # e.g. 'manfests/setup'
  # assumes root of build directory
  kubectl apply -f $path
}

function applyRegexManifests() {
  local regexPath=$1 # e.g. 'manfests/prom-*.yaml'
  # assumes root of build directory
  for file in $regexPath; do
    kubectl apply -f $file
  done
}

function cleanUp() {
  # Make sure to remove json files
  find manifests -type f ! -name '*.yaml' -delete
  rm -f kustomization
  popd >/dev/null
}

###
# Main
###
trap cleanUp EXIT

function install_prometheus() {
  # Generates YAML
  setupManifests
  setupVendors
  jsonnetBuild "prometheus.jsonnet"

  # Creates CRDs
  createCRDs

  # context: we are within the operator/build/ directory
  applyManifests "manifests/"
}

if [[ -z $(kubectl get crds | grep "prometheus") ]]; then
    echo "[INFO]: Installing Prometheus.."
    install_prometheus
else
    echo "[INFO]: Prometheus CRDs already exists. Continuing.."
fi
