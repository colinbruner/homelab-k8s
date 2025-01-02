#!/bin/bash -e

function cleanup_secrets() {
  unset OP_CONNECT_TOKEN
  rm -f $CREDENTIALS_FILE
}

trap cleanup_secrets EXIT

# Create deployment namespace
kubectl apply -k .

# Add helm repo
helm repo add 1password https://1password.github.io/connect-helm-charts/ --force-update

# get 1password operator credentials
CREDENTIALS_FILE="1password-credentials.json"
OP_CONNECT_TOKEN=$(op read "op://homelab/1Password Operator Creds/op connect token")
op document get --vault homelab "1Password Operator Creds" --out-file $CREDENTIALS_FILE

# Download 1password-credentials.json from 1Password Operator Creds entry
helm install connect 1password/connect \
  --namespace 1password \
  --set-file connect.credentials=$CREDENTIALS_FILE \
  --set operator.create=true \
  --set operator.token.value=$OP_CONNECT_TOKEN

# Upgrading
#$ helm upgrade connect 1password/connect \
#  --namespace 1password \
#  --set-file connect.credentials=$CREDENTIALS_FILE \
#  --set operator.create=true \
#  --set operator.token.value=$OP_CONNECT_TOKEN
