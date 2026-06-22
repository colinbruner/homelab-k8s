# Beszel

## Purpose

Lightweight server monitoring for the cluster. The Beszel hub provides a dashboard at `dashboard.colinbruner.com` and agents run on every node to collect system metrics.

## How it works

This component deploys two pieces:

- **Hub** -- an external Beszel hub running outside the cluster (at `192.168.1.4` / `192.168.10.4`), exposed to the cluster via a headless Service + manual Endpoints on port 443. A `BackendTLSPolicy` enables TLS verification against the hub. An `HTTPRoute` routes `dashboard.colinbruner.com` and `dashboard-internal.colinbruner.com` through the shared Gateway to the hub.
- **Agent DaemonSet** -- `henrygd/beszel-agent:latest` runs on every node (including control-plane nodes via tolerations). Agents use `hostNetwork`, `hostPID`, and mount `/proc`, `/sys`, `/etc/os-release`, and the containerd socket to collect system metrics. Each agent listens on host port 45876 and authenticates with a shared public key from the `beszel-agent-key` secret.

The namespace uses `privileged` pod security policy to allow the agent's host access.

## Dependencies

- **1password** -- operator must be running to provision the `beszel-agent-key` secret.
- **gateway** -- the shared Gateway and `dashboard-tls` certificate must exist for the HTTPRoute.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `apps`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n beszel
  kubectl get daemonset beszel-agent -n beszel
  kubectl get httproute beszel -n beszel
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n beszel -l app=beszel-agent --tail=20
  kubectl describe endpoints beszel-hub -n beszel
  ```

## Secrets

| Secret | Key | Source |
|---|---|---|
| `beszel-agent-key` | `public_key` | OnePasswordItem (`vaults/lab/items/beszel-agent-key`) |
