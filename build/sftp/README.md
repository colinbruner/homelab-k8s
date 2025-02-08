# SFTP

Just recently grabbed the [UNAS Pro][unas] from UniFi, and its been great! One missing feature (for now) has been SFTP, to support document uploads from a [network scanner][scanner] that I have.

This builds a container with SFTP installed that I intend to run within my home Kubernetes cluster and mount an NFS PV bound to my UNAS Pro server.

## Regarding the Scanner

Blindly configuring the SFTP Server so the old ass algo's used by the scanner would work was.. not a lot of fun.

Key Points for myself if I ever need to read this in the future:

- need to upload SFTP Server Hostkey pubkey to scanner
- the Hostkey must be RSA (2048 works), ed25519 does not work
- need to generate a Client Keypair on scanner, download pubkey, add to authorized_keys for SFTP Server
- The SFTP Server must permit ssh-rsa for BOTH `HostKeyAlgorithms` and `PubkeyAcceptedAlgorithms` (this was VERY painful to figure out)

Other than that, should just need 22/tcp network connectivity and the target user created for SFTP client connection.

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

[unas]: https://store.ui.com/us/en/products/unas-pro
[scanner]: https://www.brother-usa.com/products/ads4700w
