#!/bin/bash -e

# Debugging
#set -x

# This script will mount ISO images that exact on filesystem and extract
# the necessary boot components (initrd, vmlinuz) to be served over HTTP

ISO_PATH=${1:-/srv/http/images}  # /srv/http/images
BOOT_PATH=${2:-/srv/tftp/images} # /srv/tftp/images
CHANGED=false

# extract ubuntu isos will extract the necessary boot files from ubuntu isos casper directory
function extract_ubuntu_isos() {
    local file=$1 # ubuntu-22.04.4-live-server-amd64.iso
    local path=$2 # /the/full/path/to/the/file.iso
    local version=$(echo $file | cut -d- -f2) # 22.04.6

    # These files should exist
    local version_path="$BOOT_PATH/ubuntu/$version"
    local vmlinuz_path="$version_path/vmlinuz"
    local initrd_path="$version_path/initrd"

    # Ensure the directory for this ISO exists
    mkdir -p $version_path

    # If these files do NOT exist, then
    if [[ ! -f $vmlinuz_path ]] || [[ ! -f $initrd_path ]]; then
        # Mount the ISO at /mnt/
        mount -o ro,loop $path /mnt
        # Copy version specific boot files
        cp /mnt/casper/vmlinuz $vmlinuz_path && chmod 644 $vmlinuz_path
        cp /mnt/casper/initrd $initrd_path && chmod 644 $initrd_path
        # unmount the ISO
        umount /mnt
        CHANGED=true
    fi
}

###
# Main
###
for path in $(find ${ISO_PATH} -name "*.iso"); do
    file=$(basename $path)
    if [[ $file =~ ^ubuntu ]]; then
        extract_ubuntu_isos $file $path
    fi
done

# Referenced by Ansible for idempotentcy
echo "$CHANGED"
