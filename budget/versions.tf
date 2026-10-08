terraform {
  required_version = ">= 1.15.8"

  # Bucket propio (fgt-lab-budget-<ACCOUNT_ID>), separado del lab: ./lab.sh
  # destroy borra el bucket del lab y no puede tocar este state.
  backend "s3" {
    key          = "fgt-lab-budget/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.56"
    }
  }
}
