#!/bin/bash


for resource in $(kubectl get SecretStores,ClusterSecretStores,ExternalSecrets --all-namespaces); do
  # TODO: Delete resource, then uninstall helm
  echo $resource
  #helm delete external-secrets --namespace external-secrets
done
