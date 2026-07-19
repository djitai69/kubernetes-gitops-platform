# Production: separate AWS account/VPC (via a separate backend/credentials
# at apply time), separate EKS cluster, production namespace only. Not
# deployed for the homework demo — reviewed as code. See docs/cost.md and
# docs/disaster-recovery.md.

module "vpc" {
  source = "../../modules/vpc"

  name                 = var.cluster_name
  cidr_block           = "10.50.0.0/16"
  azs                  = var.azs
  public_subnet_cidrs  = ["10.50.0.0/24", "10.50.1.0/24", "10.50.2.0/24"]
  private_subnet_cidrs = ["10.50.16.0/20", "10.50.32.0/20", "10.50.48.0/20"]
  single_nat_gateway   = false
  cluster_name         = var.cluster_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  # Private-only API endpoint. Administrative access is via VPN, a private
  # runner, or SSM-managed tooling — never a public CIDR allowlist.
  endpoint_public_access       = false
  endpoint_public_access_cidrs = []

  platform_node_min_size     = 3
  platform_node_max_size     = 6
  platform_node_desired_size = 3
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "node-api"
  retention_count = 50
}

module "iam" {
  source = "../../modules/iam"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  github_org        = var.github_org
  github_repo       = var.github_repo

  eso_namespaces = {
    node-api-production = "node-api/production/"
  }
}

module "addons" {
  source = "../../modules/addons"

  cluster_name            = module.eks.cluster_name
  ebs_csi_driver_role_arn = module.iam.ebs_csi_driver_role_arn
}

module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name = module.eks.cluster_name
}
