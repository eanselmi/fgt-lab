locals {
  fortigate_ami_id  = var.lab_phase == "2" ? data.aws_ami.fortigate_payg.id : data.aws_ami.fortigate_byol.id
  fgt_instance_type = var.lab_phase == "2" ? var.fgt_instance_type_payg : var.fgt_instance_type_byol
}

module "site" {
  source   = "./modules/vpc"
  for_each = var.sites

  name                 = each.key
  vpc_cidr             = each.value.vpc_cidr
  public_subnet_cidrs  = each.value.public_subnet_cidrs
  private_subnet_cidrs = each.value.private_subnet_cidrs

  az_names = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Site = each.key
  }
}

module "compute" {
  source   = "./modules/compute"
  for_each = var.sites

  name                   = each.key
  vpc_id                 = module.site[each.key].vpc_id
  public_subnet_id       = module.site[each.key].public_subnet_ids[0]
  private_subnet_id      = module.site[each.key].private_subnet_ids[0]
  private_route_table_id = module.site[each.key].private_route_table_id

  fortigate_ami_id       = local.fortigate_ami_id
  windows_ami_id         = data.aws_ssm_parameter.windows.value
  fgt_instance_type      = local.fgt_instance_type
  windows_instance_type  = var.windows_instance_type
  windows_admin_password = var.windows_admin_password
  admin_cidr             = var.admin_cidr
  lab_cidrs              = [for s in var.sites : s.vpc_cidr]
  ssm_instance_profile   = aws_iam_instance_profile.ssm.name

  tags = {
    Site = each.key
  }
}
