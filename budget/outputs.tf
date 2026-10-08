output "budget_alert" {
  description = "Alerta de gasto real de bolsillo (budget mensual de 1 USD)."
  value       = "budget 1 USD/mes, aviso al 50% y al 100% -> ${var.alert_email} (confirma el email de AWS Notifications)"
}

output "credit_alert" {
  description = "Alerta cuando quedan menos de 10 USD de creditos (aprox)."
  value       = "aviso al quedar < 10 USD de ${var.credit_total} USD de creditos (desde ${aws_budgets_budget.credits.time_period_start}) -> ${var.alert_email}"
}
