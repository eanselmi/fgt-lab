variable "project_name" {
  description = "Nombre de proyecto, usado para tags y nombres de recursos."
  type        = string
  default     = "fgt-lab"
}

variable "fgt_instance_type" {
  description = "Tipo de instancia para el FortiGate BYOL."
  type        = string
  default     = "t3.small"
}

variable "windows_instance_type" {
  description = "Tipo de instancia para el Windows workstation."
  type        = string
  default     = "t3.medium"
}

variable "admin_cidr" {
  description = "CIDR permitido para administrar el FortiGate (HTTPS/SSH/ICMP). Por defecto abierto; conviene restringirlo a tu IP."
  type        = string
  default     = "0.0.0.0/0"
}

variable "fortigate_ami_name_filter" {
  description = "Filtro de nombre para la AMI del FortiGate BYOL (excluye el PAYG 'AWSONDEMAND')."
  type        = string
  default     = "FortiGate-VM64-AWS build*"
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
