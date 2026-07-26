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

output "fortigate_public_ips" {
  description = "EIPs (WAN1/WAN2) de cada FortiGate. Admin: https://<WAN1>, user admin, password = instance-id."
  value = {
    for name, m in module.compute : name => m.fortigate_public_ips
  }
}

output "fortigate_instance_ids" {
  description = "IDs de instancia de cada FortiGate (el instance-id es el password inicial de admin)."
  value = {
    for name, m in module.compute : name => m.fortigate_instance_id
  }
}

output "windows" {
  description = "Windows por sitio: instance-id (para SSM) e IP privada."
  value = {
    for name, m in module.compute : name => {
      instance_id = m.windows_instance_id
      private_ip  = m.windows_private_ip
      ssm_hint    = "aws ssm start-session --target ${m.windows_instance_id}"
    }
  }
}
