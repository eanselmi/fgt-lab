# Budgets es un servicio global; el topic SNS de las alertas va en us-east-1.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
