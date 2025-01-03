#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

pushd $SCRIPTPATH/build >/dev/null

kubens monitoring
kubectl delete --ignore-not-found=true -f manifests/ -f manifests/setup

popd >/dev/null
