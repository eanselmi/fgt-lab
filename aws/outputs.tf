output "region" {
  description = "Región AWS en la que se desplegó el lab."
  value       = data.aws_region.current.region
}

output "account_id" {
  description = "ID de la cuenta AWS actual."
  value       = data.aws_caller_identity.current.account_id
}

output "sites" {
  description = "IDs de red (VPC, subnets, IGW) por sitio."
  value = {
    for name, m in module.site : name => {
      vpc_id             = m.vpc_id
      igw_id             = m.igw_id
      public_subnet_ids  = m.public_subnet_ids
      private_subnet_ids = m.private_subnet_ids
    }
  }
}
