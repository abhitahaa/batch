MIME-Version: 1.0

Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/cloud-config; charset="us-ascii"

packages:
- amazon-efs-utils

runcmd:

- mkdir -p ${efs_directory}
- echo "${efs_id}:/ ${efs_directory} efs _netdev,tls,iam 0 0" >> /etc/fstab
- mount -a -t efs defaults

--==MYBOUNDARY==--