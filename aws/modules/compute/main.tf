# Security group único del sitio, totalmente abierto: es un lab para aprender
# FortiGate, así que el control de tráfico lo hace el FortiGate y no AWS (VIP,
# DNAT, IPsec, admin, etc. funcionan sin tocar nada en AWS). Lo usan el
# FortiGate, el Windows y el FortiAnalyzer.
resource "aws_security_group" "lab" {
  name_prefix = "${var.name}-lab-open-"
  description = "Lab FortiGate: todo abierto, el filtrado lo hace el FortiGate"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-lab-open"
  })
}

resource "aws_vpc_security_group_ingress_rule" "all" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Mapeo de puertos del FortiGate (fijo en todas las fases, para que un
# backup/restore entre BYOL y PAYG no cambie los nombres de interfaz):
#   port1 = WAN1 (subnet pública 1)
#   port2 = LAN  (subnet privada, gateway del Windows)
#   port3 = WAN2 (subnet pública 2, solo cuando enable_wan2; para SD-WAN/ECMP)
resource "aws_network_interface" "wan1" {
  subnet_id       = var.wan1_subnet_id
  security_groups = [aws_security_group.lab.id]

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-wan1"
  })
}

resource "aws_network_interface" "lan" {
  subnet_id       = var.lan_subnet_id
  security_groups = [aws_security_group.lab.id]
  # Única interfaz donde hace falta: el FortiGate rutea tráfico del Windows
  # cuyo destino no es la IP de esta ENI. En las WAN el FGT hace SNAT y el
  # IPsec llega a la propia IP, así que ahí se deja el default (habilitado).
  source_dest_check = false

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-lan"
  })
}

resource "aws_network_interface" "wan2" {
  count = var.enable_wan2 ? 1 : 0

  subnet_id       = var.wan2_subnet_id
  security_groups = [aws_security_group.lab.id]

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-wan2"
  })
}

resource "aws_eip" "wan1" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-wan1"
  })
}

resource "aws_eip" "wan2" {
  count  = var.enable_wan2 ? 1 : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-wan2"
  })
}

resource "aws_eip_association" "wan1" {
  allocation_id        = aws_eip.wan1.id
  network_interface_id = aws_network_interface.wan1.id
}

resource "aws_eip_association" "wan2" {
  count                = var.enable_wan2 ? 1 : 0
  allocation_id        = aws_eip.wan2[0].id
  network_interface_id = aws_network_interface.wan2[0].id
}

resource "aws_instance" "fortigate" {
  ami           = var.fortigate_ami_id
  instance_type = var.fgt_instance_type

  # El bloque network_interface está deprecado en el provider 6.x, pero se
  # mantiene a propósito: FortiOS detecta sus puertos en el boot, así que las
  # ENI tienen que estar adjuntas al lanzar la instancia (con
  # aws_network_interface_attachment llegarían después y harían falta reboots).
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.wan1.id
  }

  network_interface {
    device_index         = 1
    network_interface_id = aws_network_interface.lan.id
  }

  dynamic "network_interface" {
    for_each = aws_network_interface.wan2
    content {
      device_index         = 2
      network_interface_id = network_interface.value.id
    }
  }

  # Discos en gp3 (20% más barato que el gp2 que traen las AMI). Los tamaños son
  # los de la AMI de FortiGate 8.0.1 (raíz 2 GB, logs 30 GB): EBS no permite
  # achicarlos por debajo del snapshot.
  root_block_device {
    volume_type = "gp3"
  }

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-fgt"
  })
}

resource "aws_instance" "windows" {
  ami                         = var.windows_ami_id
  instance_type               = var.windows_instance_type
  subnet_id                   = var.lan_subnet_id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  iam_instance_profile        = var.ssm_instance_profile
  associate_public_ip_address = false

  # gp3 en vez del gp2 de la AMI (20% más barato, mismo tamaño).
  root_block_device {
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/windows-userdata.yaml.tftpl", {
    admin_password = var.windows_admin_password
    hostname       = var.windows_hostname
    is_dc          = var.windows_is_dc
    domain_name    = var.ad_domain_name
    netbios_name   = var.ad_netbios_name
  })

  # La AMI de Windows sale del parámetro SSM "latest", que cambia cada mes.
  # Sin esto, cualquier re-deploy recrearía el Windows (y el AD del SITE-A).
  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-win"
  })
}

resource "aws_route" "private_default" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.lan.id
}
