#!/bin/bash

# dumb lazy script for troubleshooting

kubectl delete pod $(kubectl get pods -l app=sftp -o yaml | yq '.items[].metadata.name')
echo "waiting 5 seconds"
sleep 5
echo "exec into pod"
kubectl exec -it $(kubectl get pods -l app=sftp -o yaml | yq '.items[].metadata.name') -- /bin/sh
