# Add non-privileged user, 'colin'
# Disable root ssh

# Disable Enterprise Registry
mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.disabled
mv /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.disabled
apt-get update
apt-get upgrade
