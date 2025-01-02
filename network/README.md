# Network

Install various network related components. Aiming to keep this pretty simple for now...

- metrics-server: components and install for kubelet metrics server
- metal-lb: DHCP based LB for handing out IP Addresses to LoadBalancer objects
- ingress-nginx: Community driven NGINX install on k8s for frontend
- cert-manager: LetsEncrypt integration for certificates

## Network Level Install

```bash
k kustomize --enable-helm . | k apply -f -
```

## Future
Maybe move cert-manager into a 'security' directory?
