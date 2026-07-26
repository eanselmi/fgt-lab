module "scheduler" {
  count   = var.shutdown_cron == "" ? 0 : 1
  source  = "eanselmi/ec2-rds-scheduler/aws"
  version = "1.0.8"

  timezone = var.shutdown_timezone

  ec2_start_stop_schedules = {
    "fgt-lab-auto-shutdown" = {
      cron_stop  = var.shutdown_cron
      cron_start = "at(2099-01-01T00:00:00)"
      tag_key    = "Project"
      tag_value  = var.project_name
    }
  }
}
