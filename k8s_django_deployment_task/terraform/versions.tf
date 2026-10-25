terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile

  allowed_account_ids = ["047472448571"]

  default_tags {
    tags = {
      Project     = local.project_name
      Environment = "lab"
      ManagedBy   = "Terraform"
    }
  }
}
