# PXC

The goal of this is to run a small LXC instance on Proxmox as a leverage point to easily stand up the rest of my homelab infrastructure. With a PXE server, I'm easily able to boot directly into Talos VMs in order to create control / worker VMs.

# Network

Configure Network Boot on the appropriate network with the following:

`{{ pxe_server_addr }} undionly.kpxe`

## Create NFS Share

Configure this in UNAS, need to remember to add 192.168.10.4 to r/w allow.

The location of the NFS Server is configurable with `nfs_server_addr` variables in the pxe role, but defaults to 192.168.10.4

# Proxmox

1. Download Debian Bookwork CT Template (rootfs)
2. Create a Proxmox LXC based off of Debian Bookworm
   2a. Add keys + password
   2b. Set privileged lxc
   2c. Set mount=nfs feature
   2d. Set IP address
3. Start Container

## Create LXC

The [provision.sh}(./provision.sh) script will create an LXC container on a target proxmox server.

```bash
# $ ./provision.sh <proxmox-host>
$ ./provision.sh 192.168.10.13
```

## Install

The [install.sh}(./install.sh) script runs the local ansible role to download necessary files and install PXE with Talos images based on a version defined within [vars/main.yml](./vars/main.yml).

```bash
# $ ./install.sh <pxe-server-ip>
$ ./install.sh 192.168.10.4
```
