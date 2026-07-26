resource "aws_security_group" "fgt" {
  name_prefix = "${var.name}-fgt-"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "fgt_https" {
  security_group_id = aws_security_group.fgt.id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "fgt_icmp" {
  security_group_id = aws_security_group.fgt.id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
}

resource "aws_vpc_security_group_ingress_rule" "fgt_ike" {
  security_group_id = aws_security_group.fgt.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "udp"
  from_port         = 500
  to_port           = 500
}

resource "aws_vpc_security_group_ingress_rule" "fgt_natt" {
  security_group_id = aws_security_group.fgt.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "udp"
  from_port         = 4500
  to_port           = 4500
}

resource "aws_vpc_security_group_ingress_rule" "fgt_esp" {
  security_group_id = aws_security_group.fgt.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "50"
}

resource "aws_vpc_security_group_ingress_rule" "fgt_internal" {
  for_each = toset(var.lab_cidrs)

  security_group_id = aws_security_group.fgt.id
  cidr_ipv4         = each.value
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "fgt_all" {
  security_group_id = aws_security_group.fgt.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "windows" {
  name_prefix = "${var.name}-win-"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-win-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "windows_internal" {
  for_each = toset(var.lab_cidrs)

  security_group_id = aws_security_group.windows.id
  cidr_ipv4         = each.value
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "windows_all" {
  security_group_id = aws_security_group.windows.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_network_interface" "wan1" {
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.fgt.id]
  source_dest_check = false

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-wan1"
  })
}

resource "aws_network_interface" "wan2" {
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.fgt.id]
  source_dest_check = false

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-wan2"
  })
}

resource "aws_network_interface" "lan" {
  subnet_id         = var.private_subnet_id
  security_groups   = [aws_security_group.fgt.id]
  source_dest_check = false

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-lan"
  })
}

resource "aws_eip" "wan1" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-fgt-wan1"
  })
}

resource "aws_eip" "wan2" {
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
  allocation_id        = aws_eip.wan2.id
  network_interface_id = aws_network_interface.wan2.id
}

resource "aws_instance" "fortigate" {
  ami           = var.fortigate_ami_id
  instance_type = var.fgt_instance_type

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.wan1.id
  }

  network_interface {
    device_index         = 1
    network_interface_id = aws_network_interface.wan2.id
  }

  network_interface {
    device_index         = 2
    network_interface_id = aws_network_interface.lan.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-fgt"
  })
}

resource "aws_instance" "windows" {
  ami                         = var.windows_ami_id
  instance_type               = var.windows_instance_type
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [aws_security_group.windows.id]
  iam_instance_profile        = var.ssm_instance_profile
  associate_public_ip_address = false

  tags = merge(var.tags, {
    Name = "${var.name}-win"
  })
}

resource "aws_route" "private_default" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.lan.id
}
