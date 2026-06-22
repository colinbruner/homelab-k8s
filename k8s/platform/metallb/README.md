# MetalLB

MetalLB provides LoadBalancer service IP addresses from a managed pool.

## Address Pools

The cluster manages two address pools:

- **Internal pool** (`192.168.10.240–242`): Default pool for shared services like the Envoy Gateway. Auto-assigned to all LoadBalancer services unless explicitly opt-in or opt-out.
- **External pool** (`192.168.10.243–245`): Opt-in pool for services requiring dedicated IPs. Requires `metallb.io/external-lb: "true"` label on the service or namespace.

## Architecture

- **Controller and speaker**: Pulled from upstream MetalLB native config (`github.com/metallb/metallb/config/native?ref=v0.15.3`), which installs the MetalLB controller and speaker DaemonSet.
- **CRs**: IPAddressPool and L2Advertisement resources are defined in this directory and applied by the same kustomization, enabling L2 mode advertising for the defined pools.

## Modification

To add or modify address pools, edit `ipaddress-pool.yaml` or `l2-advertisement.yaml` and push to git. ArgoCD will reconcile the changes.
