variable "name" {
  description = "Nombre del sitio (p. ej. SITE-A). Se usa como prefijo de los nombres de recursos."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR del VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las subnets públicas, en orden: [WAN1, WAN2] del FortiGate."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las subnets privadas; la primera es la LAN (FortiGate + Windows)."
  type        = list(string)
}

variable "az_name" {
  description = "AZ de todas las subnets. Van todas en la misma AZ porque las ENI del FortiGate tienen que estar en la AZ de la instancia."
  type        = string
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del módulo."
  type        = map(string)
  default     = {}
}
