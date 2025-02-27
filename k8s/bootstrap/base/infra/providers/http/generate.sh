#!/bin/bash

TEMP_DIR="temp_outputs"
function generate_resources() {
  mkdir -p {resources/cloudflare/,$TEMP_DIR}

  helm template -f values.yaml templates/cloudflare --output-dir=$TEMP_DIR >/dev/null

  rm -f resources/cloudflare/*.yaml
  mv $TEMP_DIR/cloudflare-http/templates/*.yaml resources/cloudflare/
  rm -rf $TEMP_DIR
}

generate_resources
