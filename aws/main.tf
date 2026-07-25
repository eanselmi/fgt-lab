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
