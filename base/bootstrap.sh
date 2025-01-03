#!/bin/bash -e

###
# Boootstrap Script
###

function install_1password() {
    # Install 1password when namespace does not exist
    if [[ ! $install_namespaces =~ "1password" ]]; then
        echo "[INFO]: Installing 1Password Operator.."
        pushd 1password >/dev/null
        ./install.sh
        popd >/dev/null
    else
        echo "[INFO]: 1Password namespace already exists. Continuing.."
    fi
}

function install_network() {
    # Forward logic to individual directories install.sh
    for path in $(find network -depth 1 -type d | sort); do 
        echo $path
        pushd $path >/dev/null
        if [[ -x ./install.sh ]]; then
            ./install.sh
        else
            echo "[WARNING]: No 'install.sh' executable was found under ${path} directory. Skipping."
        fi
        popd >/dev/null
    done
}

function install_component() {
    local name=$1
    local path=$2
    local args=$3
    echo "[INFO]: Installing ${name}."
    echo kustomize build $path $args | kubectl apply -f -
}


###
# Main
###
install_1password
install_network

## Monitoring
#configure_prometheus

#echo "[INFO]: Installing remaining components.."
#install_component "Grafana" "monitoring/grafana/" "--enable-helm" 
#install_component "Prometheus" "monitoring/prometheus/"

#kustomize build --enable-helm . | kubectl apply --force-conflicts --overwrite=true --server-side -f -

