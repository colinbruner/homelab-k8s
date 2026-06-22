# Ollama

## Purpose

Runs a local LLM inference server on the cluster, providing an OpenAI-compatible API for other services to consume.

## How it works

A single-replica Deployment runs `ollama/ollama:latest`, pinned to `worker-06` via `nodeSelector` (the node with the most available memory). An init container pulls the `llama3.2:3b` model on startup. The server listens on port 11434, exposed as a ClusterIP Service.

Model data is persisted on a 10Gi PVC backed by the `nfs-csi` StorageClass so models survive pod restarts.

Resource limits: 1800m CPU, 3Gi memory (both init and runtime containers).

## Dependencies

- **csi-nfs** -- the `nfs-csi` StorageClass must exist for the data PVC.
- Node `worker-06` must be available in the cluster.

## Operations

- **Deploy:** Managed by ArgoCD (applicationset `apps`). Synced from this directory.
- **Verify:**
  ```bash
  kubectl get pods -n ollama
  kubectl get pvc -n ollama
  ```
- **Troubleshoot:**
  ```bash
  kubectl logs -n ollama deploy/ollama --tail=50
  kubectl describe pod -n ollama -l app=ollama
  ```
- **Common tasks:**
  ```bash
  # List loaded models
  kubectl exec -n ollama deploy/ollama -- ollama list

  # Pull a new model
  kubectl exec -n ollama deploy/ollama -- ollama pull <model-name>

  # Test inference
  kubectl exec -n ollama deploy/ollama -- curl -s http://localhost:11434/api/tags
  ```

## Secrets

None.
