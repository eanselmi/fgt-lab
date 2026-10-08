variable "project_name" {
  description = "Nombre de proyecto: prefijo de los budgets y del topic SNS. Debe coincidir con PROJECT en lab.sh."
  type        = string
  default     = "fgt-lab"
}

variable "alert_email" {
  description = "Email del alumno para las alertas (via SNS). Lo pide ./lab.sh budget deploy."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email debe ser una direccion de correo valida."
  }
}

variable "credit_total" {
  description = "Total de creditos del Free Tier del alumno (USD). Se usa para avisar cuando quedan menos de 10. Cuentas nuevas: 100 base, hasta 200 completando actividades."
  type        = number
  default     = 200
}

variable "credits_start" {
  description = "Inicio (YYYY-MM-01_00:00, UTC) del budget de créditos: el primer mes con consumo de la cuenta. Lo detecta lab.sh con Cost Explorer. Vacío = día 1 del mes del primer deploy de este stack."
  type        = string
  default     = ""

  validation {
    condition     = var.credits_start == "" || can(regex("^[0-9]{4}-[0-9]{2}-01_00:00$", var.credits_start))
    error_message = "credits_start debe tener el formato YYYY-MM-01_00:00 (o estar vacío)."
  }
}
