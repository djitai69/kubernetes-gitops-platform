variable "cluster_name" {
  type = string
}

# EKS-managed addons only. AWS Load Balancer Controller, ExternalDNS,
# Karpenter, Kyverno, External Secrets Operator, and Reloader are deployed
# by Flux from the GitOps repository, not by Terraform — Flux is the only
# normal deployment actor (see decisions doc section 18/30). This module's
# job is limited to what genuinely must exist before Flux can even run:
# the CNI, DNS, kube-proxy, and the EBS CSI driver.
variable "vpc_cni_version" {
  type    = string
  default = null
}

variable "coredns_version" {
  type    = string
  default = null
}

variable "kube_proxy_version" {
  type    = string
  default = null
}

variable "ebs_csi_driver_version" {
  type    = string
  default = null
}

variable "ebs_csi_driver_role_arn" {
  description = "IRSA role for the EBS CSI driver controller"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
