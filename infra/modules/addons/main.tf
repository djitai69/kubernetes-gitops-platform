resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_version
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

locals {
  # The stable platform node group (infra/modules/eks) is tainted
  # node-role=platform:NoSchedule so application workloads don't land
  # there. Until Karpenter is deployed (by Flux, not Terraform), this is
  # the *only* node group that exists — so every addon that must run
  # somewhere needs a matching toleration, or it schedules nowhere and
  # goes DEGRADED. vpc-cni and kube-proxy ship as DaemonSets with a
  # built-in EKS toleration for all taints; coredns and the EBS CSI
  # driver's controller Deployment do not, and need it added explicitly.
  platform_toleration = [{
    key      = "node-role"
    operator = "Equal"
    value    = "platform"
    effect   = "NoSchedule"
  }]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.coredns_version
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    tolerations = local.platform_toleration
  })
  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_version
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_driver_version
  service_account_role_arn    = var.ebs_csi_driver_role_arn
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    controller = {
      tolerations = local.platform_toleration
    }
  })
  tags = var.tags
}
