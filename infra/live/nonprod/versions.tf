terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config — bucket is deliberately omitted here (it
  # would otherwise be the one piece of account-identifying data baked
  # into the repo) and supplied at `terraform init` time instead:
  #   terraform init -backend-config="bucket=<your-bucket>"
  # scripts/cloud-up.sh does this automatically.
  backend "s3" {
    key          = "node-api-platform/nonprod/terraform.tfstate"
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
      Environment = "nonprod"
      ManagedBy   = "terraform"
    }
  }
}
