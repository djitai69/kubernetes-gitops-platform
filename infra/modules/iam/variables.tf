variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Issuer URL without the https:// prefix"
  type        = string
}

variable "eso_namespaces" {
  description = "Map of namespace => Secrets Manager path prefix it may read (least privilege, one IAM role per namespace)"
  type        = map(string)
  default     = {}
}

variable "github_org" {
  description = "GitHub org/user for the OIDC-trusted CI role"
  type        = string
  default     = ""
}

variable "github_repo" {
  type    = string
  default = ""
}

variable "enable_github_actions_oidc" {
  type    = bool
  default = true
}

variable "create_github_oidc_provider" {
  description = "False to reuse an existing account-wide token.actions.githubusercontent.com OIDC provider instead of creating a new one (IAM OIDC providers are account-global; an account can only have one per URL)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
