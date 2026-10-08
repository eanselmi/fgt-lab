variable "project_name" {
  description = "Nombre de proyecto, usado para tags y nombres de recursos."
  type        = string
  default     = "fgt-lab"
}

variable "lab_phase" {
  description = "Fase del lab: '1' = ambos FortiGate BYOL (eval); '2' = el FortiGate de payg_site pasa a PAYG (trial) con WAN2, y se agrega el FortiAnalyzer."
  type        = string
  default     = "1"

  validation {
    condition     = contains(["1", "2"], var.lab_phase)
    error_message = "lab_phase debe ser '1' (BYOL) o '2' (PAYG)."
  }
}

variable "fgt_instance_type_byol" {
  description = "Tipo de instancia del FortiGate en fase 1 (BYOL eval). La licencia eval permite maximo 1 vCPU / 2 GB, por eso t2.small; las t3.* arrancan en 2 vCPU."
  type        = string
  default     = "t2.small"
}

variable "fgt_instance_type_payg" {
  description = "Tipo de instancia del FortiGate PAYG (fase 2). FortiGuard necesita >=4 GB o entra en conserve mode; c6i.large (2 vCPU / 4 GB) es el minimo real."
  type        = string
  default     = "c6i.large"
}

variable "windows_instance_type" {
  description = "Tipo de instancia para el Windows workstation."
  type        = string
  default     = "t3.medium"
}

variable "windows_admin_password" {
  description = "Password del usuario Administrator del Windows (y del dominio/DSRM en el DC). La aplica el user_data en cada arranque."
  type        = string
  default     = "Fortinet1!"
  sensitive   = true
}

variable "alert_email" {
  description = "Email del alumno para la alerta de budget (via SNS). Lo pide lab.sh en el deploy. Vacio = sin alerta."
  type        = string
  default     = ""

  validation {
    condition     = var.alert_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email debe ser una direccion de correo valida."
  }
}

variable "credit_total" {
  description = "Total de creditos del Free Tier del alumno (USD). Se usa para avisar cuando quedan menos de 10. Cuentas nuevas: 100 base, hasta 200 completando actividades."
  type        = number
  default     = 200
}

variable "shutdown_cron" {
  description = "Expresion cron del apagado automatico diario (guardrail). La arma lab.sh con la hora (0-23) que indica el alumno; siempre en punto (minuto 0)."
  type        = string
  default     = "cron(0 23 ? * * *)"
}

variable "shutdown_timezone" {
  description = "Zona horaria para el apagado automatico (formato IANA, p. ej. America/Argentina/Buenos_Aires)."
  type        = string
  default     = "America/Argentina/Buenos_Aires"
}

variable "fortios_version" {
  description = "Versión de FortiOS de las AMI del FortiGate (BYOL y PAYG). Fija para que todo el curso use la misma GUI."
  type        = string
  default     = "8.0.1"
}

variable "fortigate_byol_ami_name_filter" {
  description = "Filtro de nombre de la AMI del FortiGate BYOL. '%s' se reemplaza por fortios_version. El espacio tras 'AWS' excluye el PAYG 'AWSONDEMAND'."
  type        = string
  default     = "FortiGate-VM64-AWS build* (%s)*"
}

variable "fortigate_payg_ami_name_filter" {
  description = "Filtro de nombre de la AMI del FortiGate PAYG / on-demand. '%s' se reemplaza por fortios_version."
  type        = string
  default     = "FortiGate-VM64-AWSONDEMAND build* (%s)*"
}

variable "payg_site" {
  description = "Sitio cuyo FortiGate pasa a PAYG (con WAN2) en la fase 2. El trial de Marketplace cubre una sola instancia."
  type        = string
  default     = "SITE-A"
}

variable "ad_site" {
  description = "Sitio cuyo Windows se promueve a domain controller."
  type        = string
  default     = "SITE-A"
}

variable "ad_domain_name" {
  description = "Nombre DNS del dominio AD del lab."
  type        = string
  default     = "fortilab.local"
}

variable "ad_netbios_name" {
  description = "Nombre NetBIOS del dominio AD del lab."
  type        = string
  default     = "FORTILAB"
}

variable "faz_version" {
  description = "Versión de la AMI de FortiAnalyzer (fase 2). Tiene que ser igual o mayor que la de FortiOS."
  type        = string
  default     = "8.0.1"
}

variable "faz_ami_name_filter" {
  description = "Filtro de nombre de la AMI de FortiAnalyzer BYOL. '%s' se reemplaza por faz_version."
  type        = string
  default     = "FortiAnalyzer-VM64-AWS build* (%s)*"
}

variable "faz_instance_type" {
  description = "Tipo de instancia del FortiAnalyzer (necesita ~8 GB de RAM)."
  type        = string
  default     = "t3.large"
}

variable "faz_log_disk_gb" {
  description = "Tamaño (GB) del disco de logs del FortiAnalyzer."
  type        = number
  default     = 30
}

variable "sites" {
  description = <<-EOT
    Definición de cada sitio (VPC). Todas las subnets van en la misma AZ.
    public_subnet_cidrs = [WAN1, WAN2]; private_subnet_cidrs = [LAN]. Los CIDRs
    de los sitios NO deben solaparse (requisito del IPsec site-to-site).
    windows_hostname: máx. 15 caracteres.
  EOT
  type = map(object({
    vpc_cidr             = string
    public_subnet_cidrs  = list(string)
    private_subnet_cidrs = list(string)
    windows_hostname     = string
  }))
  default = {
    "SITE-A" = {
      vpc_cidr             = "10.210.0.0/16"
      public_subnet_cidrs  = ["10.210.0.0/24", "10.210.1.0/24"]
      private_subnet_cidrs = ["10.210.10.0/24"]
      windows_hostname     = "SITEA-DC"
    }
    "SITE-B" = {
      vpc_cidr             = "10.220.0.0/16"
      public_subnet_cidrs  = ["10.220.0.0/24", "10.220.1.0/24"]
      private_subnet_cidrs = ["10.220.10.0/24"]
      windows_hostname     = "SITEB-WIN"
    }
  }
}
