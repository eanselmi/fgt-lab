variable "name" {
  description = "Nombre del sitio (p. ej. SITE-A). Se usa como prefijo de los nombres de recursos."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR del VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Lista de CIDRs para las subnets públicas (una por AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Lista de CIDRs para las subnets privadas (una por AZ)."
  type        = list(string)
}

variable "az_names" {
  description = "Lista de AZs a usar; la subnet de índice i va a la AZ de índice i."
  type        = list(string)
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del módulo."
  type        = map(string)
  default     = {}
}
