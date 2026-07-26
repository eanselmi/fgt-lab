variable "project_name" {
  description = "Nombre de proyecto, usado para tags y nombres de recursos."
  type        = string
  default     = "fgt-lab"
}

variable "lab_phase" {
  description = "Fase del lab: '1' = FortiGate BYOL (eval), '2' = FortiGate PAYG (free trial). Cambia la AMI y el tipo de instancia del FortiGate."
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
  description = "Tipo de instancia del FortiGate en fase 2 (PAYG). FortiGuard necesita >=4 GB o entra en conserve mode; c6i.large (2 vCPU / 4 GB) es el minimo real."
  type        = string
  default     = "c6i.large"
}

variable "windows_instance_type" {
  description = "Tipo de instancia para el Windows workstation."
  type        = string
  default     = "t3.medium"
}

variable "windows_admin_password" {
  description = "Password del usuario Administrator del Windows, aplicada por user_data en el primer arranque."
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

variable "admin_cidr" {
  description = "CIDR permitido para administrar el FortiGate (HTTPS/SSH/ICMP). Por defecto abierto; conviene restringirlo a tu IP."
  type        = string
  default     = "0.0.0.0/0"
}

variable "fortigate_byol_ami_name_filter" {
  description = "Filtro de nombre para la AMI del FortiGate BYOL (fase 1). El espacio tras 'AWS' excluye el PAYG 'AWSONDEMAND'."
  type        = string
  default     = "FortiGate-VM64-AWS build*"
}

variable "fortigate_payg_ami_name_filter" {
  description = "Filtro de nombre para la AMI del FortiGate PAYG / on-demand (fase 2)."
  type        = string
  default     = "FortiGate-VM64-AWSONDEMAND build*"
}

variable "sites" {
  description = <<-EOT
    Definición de cada sitio (VPC): CIDR del VPC y CIDRs de las subnets públicas
    y privadas. Cada lista debe tener 2 elementos (uno por AZ). Los CIDRs de los
    dos sitios NO deben solaparse (requisito para el futuro IPsec site-to-site).
  EOT
  type = map(object({
    vpc_cidr             = string
    public_subnet_cidrs  = list(string)
    private_subnet_cidrs = list(string)
  }))
  default = {
    "SITE-A" = {
      vpc_cidr             = "10.210.0.0/16"
      public_subnet_cidrs  = ["10.210.0.0/24", "10.210.1.0/24"]
      private_subnet_cidrs = ["10.210.10.0/24", "10.210.11.0/24"]
    }
    "SITE-B" = {
      vpc_cidr             = "10.220.0.0/16"
      public_subnet_cidrs  = ["10.220.0.0/24", "10.220.1.0/24"]
      private_subnet_cidrs = ["10.220.10.0/24", "10.220.11.0/24"]
    }
  }
}
