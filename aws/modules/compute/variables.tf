variable "name" {
  description = "Nombre del sitio (p. ej. SITE-A). Prefijo de nombres de recursos."
  type        = string
}

variable "vpc_id" {
  description = "ID del VPC del sitio."
  type        = string
}

variable "wan1_subnet_id" {
  description = "ID de la subnet pública de WAN1 (port1 del FortiGate)."
  type        = string
}

variable "wan2_subnet_id" {
  description = "ID de la subnet pública de WAN2 (port3 del FortiGate). Misma AZ que WAN1."
  type        = string
}

variable "lan_subnet_id" {
  description = "ID de la subnet privada donde van la LAN del FortiGate (port2) y el Windows."
  type        = string
}

variable "private_route_table_id" {
  description = "ID de la route table privada, para la default route hacia la LAN del FortiGate."
  type        = string
}

variable "enable_wan2" {
  description = "Crea la 3ra ENI (WAN2, port3) con su EIP. Solo en el FortiGate PAYG: la licencia eval BYOL admite 3 interfaces en total y hay que dejar una libre para el túnel IPsec."
  type        = bool
  default     = false
}

variable "fortigate_ami_id" {
  description = "ID de la AMI del FortiGate (BYOL o PAYG)."
  type        = string
}

variable "windows_ami_id" {
  description = "ID de la AMI del Windows."
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
  description = "Password del usuario Administrator del Windows (y DSRM del AD)."
  type        = string
  sensitive   = true
}

variable "windows_hostname" {
  description = "Hostname del Windows (máx. 15 caracteres, NetBIOS)."
  type        = string
}

variable "windows_is_dc" {
  description = "Promueve el Windows a domain controller (AD DS + DNS + NPS)."
  type        = bool
  default     = false
}

variable "ad_domain_name" {
  description = "Nombre DNS del dominio AD (solo si windows_is_dc)."
  type        = string
}

variable "ad_netbios_name" {
  description = "Nombre NetBIOS del dominio AD (solo si windows_is_dc)."
  type        = string
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
