#!/bin/bash -e

ONEPASSWORD_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function cleanup_secrets() {
  unset OP_CONNECT_TOKEN
  rm -f $CREDENTIALS_FILE
}

trap cleanup_secrets EXIT


function install_1password() {
    # Create deployment namespace
    kubectl apply -k $ONEPASSWORD_DIR

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

    # Wait until CRDS are ready
    kubectl wait --for condition=established --timeout=60s crds/onepassworditems.onepassword.com
}

if [[ ! $(kubens | grep "1password") == "1password" ]]; then
    echo "[INFO]: Installing 1Password Operator.."
    echo ./1password/install.sh
else
    echo "[INFO]: 1Password namespace already exists. Continuing.."
fi

exit
