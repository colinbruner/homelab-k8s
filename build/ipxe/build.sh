#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

# Sanity
if [[ uname != Linux ]] && [[ ! $(which apt-get) ]]; then
    echo "[ERROR]: Unsupported OS, please use Ubuntu/Debian"
    exit 1
fi

function install_deps() {
    apt-get update && apt-get install build-essential git liblzma-dev -y
}

function clone_ipxe() {
    # NOTE: I originally had this as a submodule, however
    # upon building I ran into this specific issue
    # https://github.com/ipxe/ipxe/discussions/382
    # 
    # so cloning this fresh build time now.
    rm -rf ${SCRIPTPATH}/ipxe
    git clone https://github.com/ipxe/ipxe
}

function build_ipxe() {
    local embedded_file="chain.ipxe" # the file to embed in built artifact
    pushd ${SCRIPTPATH}/ipxe/src
    echo "Building undionly.kpxe"
    make bin/undionly.kpxe EMBED=${SCRIPTPATH}/$embedded_file
    
    popd
    echo "Moving undionly.kpxe to ./bin/"
    mkdir -p bin
    mv ipxe/src/bin/undionly.kpxe ./bin/
}

install_deps
clone_ipxe
build_ipxe
