Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0
--==BOUNDARY==
Content-Type: text/cloud-boothook; charset="us-ascii"
#cloud-boothook
#!/bin/bash
cloud-init-per once docker_options echo 'OPTIONS="$${OPTIONS} --storage-opt dm.basesize=20G"' >> /etc/sysconfig/docker
--==BOUNDARY==
Content-Type: text/cloud-config; charset="us-ascii"
packages:
- amazon-efs-utils
runcmd:
- mkdir -p ${efs_directory}
- echo "${efs_id}:/ ${efs_directory} efs _netdev,tls,iam 0 0" >> /etc/fstab
- mount -a -t efs defaults
--==BOUNDARY==--