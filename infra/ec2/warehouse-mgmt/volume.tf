// --- EBS Volume

# Note:
# The intended use case here is that EBS volume for storing some temporary data.
# Once the activity is completed, offload the data to S3 for long term storage or further use.
# Detach and tear down the EBS volume.
# ~victor

# ---
# Uncomment below to create EBS volume

# resource "aws_ebs_volume" "mgmt_ebs1" {
#  availability_zone = "ap-southeast-2a"
#  size              = 200  # in GB
#
#  tags = {
#    Name = "${local.stack_name}-mgmt-instance-ebs1"
#  }
# }
#
# resource "aws_volume_attachment" "mgmt_ebs1_attach" {
#  device_name = "/dev/sdh"
#  volume_id   = aws_ebs_volume.mgmt_ebs1.id
#  instance_id = aws_instance.mgmt.id
# }




# ---
# Login to instance to format and mount the EBS volume like so

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
