#!/bin/bash

# absolute path to the helm chart
HELM_CHART=$(git rev-parse --show-toplevel)/k8s/packages/helm/cloudflare
TEMP_DIR="temp_outputs"
function generate_resources() {
  mkdir -p {resources/cloudflare/,$TEMP_DIR}

  helm template -f values.yaml $HELM_CHART --output-dir=$TEMP_DIR >/dev/null

  rm -f resources/cloudflare/*.yaml
  mv $TEMP_DIR/cloudflare-http/templates/*.yaml resources/cloudflare/
  rm -rf $TEMP_DIR
}

generate_resources
