# MetalLB

## Purpose

Provides LoadBalancer service IP addresses for the bare-metal cluster. Without MetalLB, Kubernetes services of type `LoadBalancer` would remain in `Pending` state.

## How it works

MetalLB is installed from the upstream native config (`github.com/metallb/metallb/config/native?ref=v0.15.3`), which deploys the controller Deployment and speaker DaemonSet in `metallb-system`. L2 mode is used (ARP-based advertisement).

Two `IPAddressPool` resources define the available address ranges:

- **`internal-lb-pool`** (`192.168.10.240-192.168.10.242`) -- default pool, auto-assigned to all LoadBalancer services. Used by the shared Envoy Gateway.
- **`external-lb-pool`** (`192.168.10.243-192.168.10.245`) -- opt-in pool for services requiring dedicated IPs. Requires `metallb.io/external-lb: "true"` label on the Service or Namespace. `autoAssign: false`.

An `L2Advertisement` resource advertises both pools.

## Dependencies

None -- MetalLB is a foundational component with no dependencies on other platform services.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `platform`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n metallb-system
  kubectl get ipaddresspools -n metallb-system
  kubectl get svc -A --field-selector spec.type=LoadBalancer
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n metallb-system -l app.kubernetes.io/name=metallb -c controller --tail=50
  kubectl describe ipaddresspool -n metallb-system
  ```
- **Common task -- modify address pools:** Edit `ipaddress-pool.yaml` and/or `l2-advertisement.yaml`, then commit and push.

## Secrets

None.
