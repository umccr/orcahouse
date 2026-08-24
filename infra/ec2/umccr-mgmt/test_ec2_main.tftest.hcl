mock_provider "aws" {}

run "assert_instance_ami_id" {
  assert {
    condition     = aws_instance.mgmt.ami == "ami-0f1329677c7e5aba8"
    error_message = "unexpected ami image id"
  }
}

run "assert_instance_type" {
  assert {
    condition     = aws_instance.mgmt.instance_type == "t4g.nano"
    error_message = "unexpected instance type"
  }
}

run "assert_no_public_ip" {
  assert {
    condition     = aws_instance.mgmt.associate_public_ip_address == false
    error_message = "unexpected public ip address"
  }
}
