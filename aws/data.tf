data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# most_recent solo desempata entre builds de la MISMA versión (fortios_version):
# el filtro de nombre fija la versión para que el curso sea homogéneo.
data "aws_ami" "fortigate_byol" {
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = [format(var.fortigate_byol_ami_name_filter, var.fortios_version)]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Solo se busca en fase 2: en fase 1 no hace falta la suscripción PAYG.
data "aws_ami" "fortigate_payg" {
  count       = var.lab_phase == "2" ? 1 : 0
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = [format(var.fortigate_payg_ami_name_filter, var.fortios_version)]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ami" "faz" {
  count       = var.lab_phase == "2" ? 1 : 0
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = [format(var.faz_ami_name_filter, var.faz_version)]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ssm_parameter" "windows" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}
