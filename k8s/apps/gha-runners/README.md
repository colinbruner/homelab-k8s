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
| Runner namespace | `gha-runners` |
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

The controller and workflow pods share the `gha-runners` namespace for
operational simplicity. Workflow pods still use a no-permission service account
and do not receive a Kubernetes service-account token.

The namespace enforces the `privileged` Pod Security level because DinD requires
a privileged Docker daemon. Baseline violations remain enabled in audit and
warning modes. Since the controller shares this namespace, only ARC resources
should be deployed into it.

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

After Argo CD syncs the `gha-runners` application:

```bash
kubectl get pods -n gha-runners
kubectl get autoscalingrunnersets -n gha-runners
```

The runner namespace normally has only the listener pod while idle because the
scale set scales runners down to zero.
