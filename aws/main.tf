locals {
  phase2 = var.lab_phase == "2"

  # Por sitio: solo payg_site pasa a PAYG (con WAN2) en fase 2; el resto sigue
  # BYOL eval con 2 ENI (WAN1 + LAN), dejando la 3ra interfaz de la licencia
  # libre para el túnel IPsec.
  site_cfg = {
    for name, s in var.sites : name => {
      payg = local.phase2 && name == var.payg_site
    }
  }

  instance_types = toset(compact([
    var.fgt_instance_type_byol,
    var.fgt_instance_type_payg,
    var.windows_instance_type,
    var.faz_instance_type,
  ]))

  # Primera AZ que ofrece todos los tipos de instancia del lab (t2.* no existe
  # en todas las AZ).
  lab_az = sort(setintersection([
    for t in local.instance_types : toset(data.aws_ec2_instance_type_offerings.lab[t].locations)
  ]...))[0]
}

data "aws_ec2_instance_type_offerings" "lab" {
  for_each      = local.instance_types
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [each.value]
  }
}

module "site" {
  source   = "./modules/vpc"
  for_each = var.sites

  name                 = each.key
  vpc_cidr             = each.value.vpc_cidr
  public_subnet_cidrs  = each.value.public_subnet_cidrs
  private_subnet_cidrs = each.value.private_subnet_cidrs
  az_name              = local.lab_az

  tags = {
    Site = each.key
  }
}

module "compute" {
  source   = "./modules/compute"
  for_each = var.sites

  name                   = each.key
  vpc_id                 = module.site[each.key].vpc_id
  wan1_subnet_id         = module.site[each.key].public_subnet_ids[0]
  wan2_subnet_id         = module.site[each.key].public_subnet_ids[1]
  lan_subnet_id          = module.site[each.key].private_subnet_ids[0]
  private_route_table_id = module.site[each.key].private_route_table_id

  enable_wan2       = local.site_cfg[each.key].payg
  fortigate_ami_id  = local.site_cfg[each.key].payg ? data.aws_ami.fortigate_payg[0].id : data.aws_ami.fortigate_byol.id
  fgt_instance_type = local.site_cfg[each.key].payg ? var.fgt_instance_type_payg : var.fgt_instance_type_byol

  windows_ami_id         = data.aws_ssm_parameter.windows.value
  windows_instance_type  = var.windows_instance_type
  windows_admin_password = var.windows_admin_password
  windows_hostname       = each.value.windows_hostname
  windows_is_dc          = each.key == var.ad_site
  ad_domain_name         = var.ad_domain_name
  ad_netbios_name        = var.ad_netbios_name
  ssm_instance_profile   = aws_iam_instance_profile.ssm.name

  tags = {
    Site = each.key
  }
}
