terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config — see infra/live/nonprod/versions.tf for why
  # bucket is omitted here and supplied at `terraform init` time instead.
  backend "s3" {
    key          = "node-api-platform/production/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "node-api-platform"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}
