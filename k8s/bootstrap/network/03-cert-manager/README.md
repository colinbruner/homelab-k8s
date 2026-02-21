# Cert Manager

## Depdendencies
- 1password operator

## Install

```bash
$ ./install.sh
```

## Requesting a Certificate
Adding the following configuration to an ingress object will create a certificate with SANs matching the `hosts` array. NGINX will automatically pick up and serve this certificate for ingress into this endpoint.
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
...
spec:
  tls:
  - hosts:
    - grafana.colinbruner.com
    secretName: grafana-tls
...
```

## Troubleshooting
Understanding the flow of cert manager is important. There are innner working diagrams at the bottom of the page [here](https://cert-manager.io/docs/usage/certificate/) as well as just good docs and diagrams explaining the process.

With my limited knowledge, upon creating the referenced ingress object above, it's something like:
```
csr -> cert -> order -> challenge
```
Where a `certificate request (csr)` creates a `cert` which places an `order` which spawns a `challenge`. Upon the `challenge` (DNS, in my case) being complete, the `order` can be fulfilled and the `certificaterequest` granted and `certificate` obtained.

The following are useful troubleshooting steps to gather error output when certificate is not showing as ready.
```bash
$ kubectl get cert
$ kubectl get certificaterequest
$ kubectl get order
$ kubectl get challenge

# More details
$ cmctl status certificate <cert>
```
