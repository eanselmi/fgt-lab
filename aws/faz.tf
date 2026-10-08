# FortiAnalyzer (fase 2), junto al FortiGate PAYG para tener logs de UTM.
# Va en la subnet pública de WAN1 de payg_site, con su propia EIP: así se
# licencia contra FortiCare sin depender de la config del FortiGate, el FGT
# local le manda logs por IP privada y el FGT del otro sitio por la EIP.
resource "aws_instance" "faz" {
  count = local.phase2 ? 1 : 0

  ami                    = data.aws_ami.faz[0].id
  instance_type          = var.faz_instance_type
  subnet_id              = module.site[var.payg_site].public_subnet_ids[0]
  vpc_security_group_ids = [module.compute[var.payg_site].security_group_id]

  root_block_device {
    volume_type = "gp3"
  }

  # Disco de logs: la AMI ya trae /dev/sdb (80 GB gp2); esto lo pasa a gp3
  # (20% más barato). No se puede achicar por debajo del snapshot de la AMI.
  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = var.faz_log_disk_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.payg_site}-faz"
    Site = var.payg_site
  }
}

resource "aws_eip" "faz" {
  count    = local.phase2 ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.faz[0].id

  tags = {
    Name = "${var.payg_site}-faz"
    Site = var.payg_site
  }
}
