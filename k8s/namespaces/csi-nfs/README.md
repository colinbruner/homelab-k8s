# csi-nfs

Installs the CSI-NFS driver and controller and a single storage class for dynamically provisioning volumes under a single NFS share.. called k8s in my case.

In addition, we create two PVs (documents and scans) to be used by PVCs and fulfilled by the nfs-csi controller for static mounting @ the root of the share.
