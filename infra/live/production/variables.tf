variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "node-api-production"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "github_org" {
  type    = string
  default = "REPLACE_WITH_OWNER"
}

variable "github_repo" {
  type    = string
  default = "kubernetes-gitops-platform"
}
