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
  description = "EIPs de cada FortiGate: wan1 = port1, wan2 = port3 (solo el PAYG en fase 2). Admin: https://<wan1>, user admin, password inicial = instance-id."
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

output "auto_shutdown" {
  description = "Guardrail de apagado automatico diario de las instancias del lab."
  value       = var.shutdown_cron == "" ? "desactivado" : "${var.shutdown_cron} (${var.shutdown_timezone})"
}

output "windows" {
  description = "Windows por sitio: instance-id (para Fleet Manager/SSM), IP privada y hostname. El de ad_site es el domain controller."
  value = {
    for name, m in module.compute : name => {
      instance_id = m.windows_instance_id
      private_ip  = m.windows_private_ip
      hostname    = var.sites[name].windows_hostname
      role        = name == var.ad_site ? "domain controller (${var.ad_domain_name}, NetBIOS ${var.ad_netbios_name}) + DNS + NPS/RADIUS" : "workstation"
    }
  }
}

output "fortianalyzer" {
  description = "FortiAnalyzer (solo fase 2). GUI: https://<public_ip>, user admin, password inicial = instance-id."
  value = local.phase2 ? {
    public_ip   = aws_eip.faz[0].public_ip
    private_ip  = aws_instance.faz[0].private_ip
    instance_id = aws_instance.faz[0].id
  } : null
}
