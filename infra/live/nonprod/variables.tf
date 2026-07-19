variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "node-api-nonprod"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "github_org" {
  type    = string
  default = "djitai69"
}

variable "github_repo" {
  type    = string
  default = "kubernetes-gitops-platform"
}
