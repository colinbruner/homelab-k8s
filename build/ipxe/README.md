# iPXE

The following is custom built src code for homelab.

We're building a custom `undionly.kpxe` file with an embedded script to break the bootloader infinite chain. This seems to be the best path forward using using Unifi's DHCP Server instead of a ISC DHCP Server on Linux.

## chain.ipxe

This file is intended to be embedded in the `undionly.kpxe` binary to break the chain loading process.
https://ipxe.org/howto/chainloading

## Building

### OSX

If runing on OSX (Silicon), run the following to get into an Ubuntu container

```bash
# or docker
$ podman run --arch=amd64 -v $(pwd):/opt -it amd64/ubuntu:latest /bin/bash
# and follow section 'Building' below.
$ cd /opt
```

## To Build

Building on Ubuntu (AMD64), the following was required:

```bash
# Build - will install prereqs and produce 'bin/undionly.kpxe'
$ ./build.sh
```

Manually (for now) move this to expected ansible file location

```bash
$ mv bin/undionly.kpxe ../../automation/ansible/pxe/roles/pxe/files
```
