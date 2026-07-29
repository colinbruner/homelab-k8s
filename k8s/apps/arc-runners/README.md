# GitHub Actions Runner Scale Set

Deploys GitHub's Actions Runner Controller (ARC) and an organization-scoped
runner scale set using the official OCI Helm charts.

## Configuration

| Setting | Value |
|---------|-------|
| ARC chart version | `0.14.2` |
| GitHub scope | `https://github.com/Bruner-Family` |
| Runner scale set | `self-homelab` |
| Controller namespace | `gha-runners` |
| Runner namespace | `arc-runners` |
| Idle runners | `0` |
| Maximum runners | `1` |
| Container mode | Docker-in-Docker |

Workflows in repositories allowed to use the organization runner group can
target the scale set with:

```yaml
jobs:
  example:
    runs-on: self-homelab
```

The runner pod uses Docker-in-Docker so workflows can run container actions and
build images. The Docker daemon is privileged, so access to this scale set must
be limited to trusted repositories and workflows.

## GitHub authentication

The 1Password operator materializes the `github-config` Kubernetes Secret from:

```text
op://lab/GHA Homelab Runner/github_token
```

The 1Password item field must remain named `github_token`, which is the key ARC
expects for PAT authentication. For an organization-scoped fine-grained PAT,
GitHub requires:

- Organization `Administration`: read
- Organization `Self-hosted runners`: read and write

The PAT must have access to the `Bruner-Family` organization. Repository access
to the runner is controlled through the organization's runner-group settings.

## Network and Kubernetes access

Workflow runner pods do not receive a Kubernetes service-account token. They
therefore have no in-cluster identity or Kubernetes RBAC permissions.

The cluster currently uses Flannel without a NetworkPolicy enforcement engine.
Kubernetes manifests cannot enforce a public-internet-only egress boundary in
the current network stack. Restrict private-network egress at the network
firewall, or add a policy-capable CNI before relying on Kubernetes
NetworkPolicies for runner isolation.

## Verification

After Argo CD syncs the `arc-runners` application:

```bash
kubectl get pods -n gha-runners
kubectl get autoscalingrunnersets -n arc-runners
kubectl get pods -n arc-runners
```

The runner namespace normally has only the listener pod while idle because the
scale set scales runners down to zero.
