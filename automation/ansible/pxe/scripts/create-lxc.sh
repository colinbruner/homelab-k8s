#!/usr/bin/env bash

# NOTE: This script is intended to be run on the Proxmox host, as root.
#       Ansible is intended to act as the task runner for this.
# There are some hardcoded attriutes here worth noting:
# - The LXC container ID is hardcoded to 1001
# - The LXC container hostname is hardcoded to "pxe"
# - The LXC container IP address is hardcoded to 192.168.1.4
# There are a few others as well, but these are the most notable.
ROOTPASS=$1
PUBKEY=$2
PUBKEY_FILE="/root/pct-1001.pub"

if [[ -z $ROOTPASS || -z $PUBKEY ]]; then
  echo "Usage: $0 <root-password> <public-key>"
  exit 1
fi

cleanup() {
  rm -f $PUBKEY_FILE
}
trap cleanup EXIT

is_running() {
  # $ pct list
  # VMID       Status     Lock         Name
  # 1001       running                 pxe
  if [[ $(pct list | grep 1001 | awk '{print $2}') == "running" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

if [[ $(is_running) == "true" ]]; then
  echo "[INFO]: pxe is already running, nothing to do."
  exit 0
fi

echo "$PUBKEY" > $PUBKEY_FILE

pct create 1001 \
  /var/lib/vz/template/cache/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname pxe \
  --memory 512 \
  --net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.10.1,ip=192.168.10.4/24,type=veth \
  --storage local-lvm \
  --rootfs local-lvm:10 \
  --features "mount=nfs" \
  --unprivileged 0 \
  --ssh-public-keys "$PUBKEY_FILE" \
  --ostype debian \
  --password="$ROOTPASS" \
  --start 1
