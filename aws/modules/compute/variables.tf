variable "name" {
  description = "Nombre del sitio (p. ej. SITE-A). Prefijo de nombres de recursos."
  type        = string
}

variable "vpc_id" {
  description = "ID del VPC del sitio."
  type        = string
}

variable "public_subnet_id" {
  description = "ID de la subnet pública (AZ-0) donde van las 2 WAN del FortiGate."
  type        = string
}

variable "private_subnet_id" {
  description = "ID de la subnet privada (AZ-0) donde van la LAN del FortiGate y el Windows."
  type        = string
}

variable "private_route_table_id" {
  description = "ID de la route table privada, para la default route hacia la LAN del FortiGate."
  type        = string
}

variable "fortigate_ami_id" {
  description = "ID de la AMI del FortiGate BYOL."
  type        = string
}

variable "windows_ami_id" {
  description = "ID de la AMI del Windows workstation."
  type        = string
}

variable "fgt_instance_type" {
  description = "Tipo de instancia del FortiGate."
  type        = string
}

variable "windows_instance_type" {
  description = "Tipo de instancia del Windows."
  type        = string
}

variable "windows_admin_password" {
  description = "Password del usuario Administrator del Windows."
  type        = string
  sensitive   = true
}

variable "admin_cidr" {
  description = "CIDR permitido para administrar el FortiGate (HTTPS/SSH/ICMP)."
  type        = string
}

variable "lab_cidrs" {
  description = "CIDRs de todos los sitios del lab, para permitir tráfico interno entre VPCs."
  type        = list(string)
}

variable "ssm_instance_profile" {
  description = "Nombre del instance profile con AmazonSSMManagedInstanceCore para el Windows."
  type        = string
}

variable "tags" {
  description = "Tags adicionales para todos los recursos del módulo."
  type        = map(string)
  default     = {}
}
