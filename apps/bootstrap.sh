#!/bin/bash -e

###
# Boootstrap Script
###

function install_namespace() {
    local ns=$1
    if [[ ! $(kubens | grep $ns) == $ns ]]; then
        kubectl apply -f $ns/namespace.yaml
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
# Initial Apps
###
# NOTE: Only these apps are 'bootstrapped', 
# everything else should be managed by ArgoCD
###
install_component "argo"
install_namespace "monitoring"
install_component "monitoring"
