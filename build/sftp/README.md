# SFTP

Just recently grabbed the [UNAS Pro][unas] from UniFi, and its been great! One missing feature (for now) has been SFTP, to support document uploads from a network scanner that I have.

This builds a container with SFTP installed that I intend to run within my home Kubernetes cluster and mount an NFS PV bound to my UNAS Pro server.

unas: https://store.ui.com/us/en/products/unas-pro

## Build Locally

```bash
$ podman build -t sftp .
```

## Test Locally

```bash
# Run
$ podman container run --name sftp -p 8022:22 localhost/sftp

# Connect
$ sftp \
    -o 'UserKnownHostsFile=/dev/null' \
    -o 'StrictHostKeyChecking=no' \
    -P 8022 \
    scanner@localhost

# Stop
$ podman container rm -f sftp
```
