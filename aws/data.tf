data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "fortigate" {
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = [var.fortigate_ami_name_filter]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ssm_parameter" "windows" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}
