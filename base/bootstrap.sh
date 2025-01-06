#!/bin/bash -e

###
# Boootstrap Script
###

function install_1password() {
    # Install 1password when namespace does not exist
    pushd 1password >/dev/null
    ./install.sh
    popd >/dev/null
}

function install_namespace() {
    local path=$1
    local ns=$2
    if [[ ! $(kubens | grep $ns) == $ns ]]; then
        kubectl apply -f $path
    fi
}

function install_component() {
    local target=$1
    # Forward logic to individual directories install.sh
    for path in $(dirname $(find $target -type f -name install.sh | sort)); do
        pushd $path >/dev/null
        if [[ -x ./install.sh ]]; then
            ./install.sh
        else
            echo "[WARNING]: No executable 'install.sh' file found for '${target}' under '${path}' directory. Skipping."
        fi
        popd >/dev/null
    done
}

###
# Base
###
install_1password
install_component "network"
install_component "infra"

###
# Argo & Monitoring
###
# TODO?
#install_namespace "monitoring/namespace.yaml" "monitoring"
#install_component "monitoring"

# NOTE: Everything else install through ArgoCD
