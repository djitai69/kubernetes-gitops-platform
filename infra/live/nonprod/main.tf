# Non-production: one AWS account/VPC, one EKS cluster, dev + staging
# namespaces. Cost trade-offs applied here: single NAT gateway, no
# production-grade retention. See docs/cost.md.

module "vpc" {
  source = "../../modules/vpc"

  name                 = var.cluster_name
  cidr_block           = "10.40.0.0/16"
  azs                  = var.azs
  public_subnet_cidrs  = ["10.40.0.0/24", "10.40.1.0/24", "10.40.2.0/24"]
  private_subnet_cidrs = ["10.40.16.0/20", "10.40.32.0/20", "10.40.48.0/20"]
  single_nat_gateway   = true
  cluster_name         = var.cluster_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  # Bootstrap-only relaxation: real usage should tighten
  # endpoint_public_access_cidrs to the operator's known egress IPs, or
  # disable public access entirely once a private access path (VPN,
  # bastion, SSM) exists.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["0.0.0.0/0"]
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "node-api"
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

module "iam" {
  source = "../../modules/iam"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  github_org        = var.github_org
  github_repo       = var.github_repo

  eso_namespaces = {
    node-api-dev     = "node-api/dev/"
    node-api-staging = "node-api/staging/"
  }
}
