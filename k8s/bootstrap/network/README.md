# Network

Install various network related components. Aiming to keep this pretty simple for now...

Each directory has an `install.sh` that captures the necessary logic required to install the specific application.

Kustomize was considered, however due to cert-manager taking sometime to create CRDs.. utilizing Kustomize by itself is not possible without error.

## Future
Maybe move cert-manager into a 'security' directory?
