// --- EBS Volume

# resource "aws_ebs_volume" "mgmt_ebs1" {
#  availability_zone = "ap-southeast-2a"
#  size              = 200  # in GB
#
#  tags = {
#    Name = "${local.stack_name}-${terraform.workspace}-mgmt-instance-ebs1"
#  }
# }
#
# resource "aws_volume_attachment" "mgmt_ebs1_attach" {
#  device_name = "/dev/sdh"
#  volume_id   = aws_ebs_volume.mgmt_ebs1.id
#  instance_id = aws_instance.mgmt.id
# }



# sudo su - root
# lsblk
# ll /dev/nvme1n1
# mkfs -t xfs /dev/nvme1n1
# blkid | grep nvme1n1
# echo "UUID=3929e761-3a60-46a8-9e52-a98a8d76b144  /data  xfs  defaults,nofail  0  2" >> /etc/fstab
# mkdir -p /data
# mount -a
# systemctl daemon-reload
# df -h
