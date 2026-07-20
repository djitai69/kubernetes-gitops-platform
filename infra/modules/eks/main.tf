data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Control plane IAM role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Control plane
# ---------------------------------------------------------------------------
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.cluster_name}-cluster" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  # Envelope encryption of Kubernetes Secrets at rest.
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

resource "aws_kms_key" "eks_secrets" {
  description             = "EKS Kubernetes Secrets envelope encryption for ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 90
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# OIDC provider for IRSA (IAM Roles for Service Accounts)
# ---------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Stable managed node group for platform components (CoreDNS, Flux,
# Karpenter, External Secrets Operator, Kyverno). On-demand, multi-AZ,
# tainted so only platform controllers with a matching toleration schedule
# here. Karpenter itself runs on this group so it does not depend on nodes
# it creates.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "platform_nodes" {
  name = "${var.cluster_name}-platform-nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "platform_nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.platform_nodes.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "platform" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "platform"
  node_role_arn   = aws_iam_role.platform_nodes.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.platform_node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = var.platform_node_min_size
    max_size     = var.platform_node_max_size
    desired_size = var.platform_node_desired_size
  }

  labels = {
    "node-role" = "platform"
  }

  # Tainting this group only makes sense once Karpenter is actually
  # deployed and providing an untainted landing zone for application
  # workloads — otherwise it's the *only* node group that exists, and
  # every component that must run somewhere (EKS-managed addons, Flux
  # itself, Helm hook Jobs from third-party charts) needs an explicit
  # toleration or it schedules nowhere. Found this the hard way: hit it
  # four separate times (coredns, the EBS CSI driver, flux install, and
  # a Kyverno Helm hook Job) bootstrapping a fresh cluster with no
  # Karpenter deployed. Default true matches the documented production
  # design; set false where Karpenter isn't part of the environment.
  dynamic "taint" {
    for_each = var.taint_platform_nodes ? [1] : []
    content {
      key    = "node-role"
      value  = "platform"
      effect = "NO_SCHEDULE"
    }
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.platform_nodes]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
