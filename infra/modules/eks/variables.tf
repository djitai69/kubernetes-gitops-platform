variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "endpoint_public_access" {
  description = "Non-prod may temporarily enable this with cidr restriction for bootstrap; production stays false"
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = []
}

variable "platform_node_instance_types" {
  description = "Small, stable, on-demand node group for CoreDNS, Flux, Karpenter, ESO, Kyverno"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "platform_node_min_size" {
  type    = number
  default = 2
}

variable "platform_node_max_size" {
  type    = number
  default = 4
}

variable "platform_node_desired_size" {
  type    = number
  default = 2
}

variable "taint_platform_nodes" {
  description = "Taint the platform node group so only tolerating workloads land there. Only meaningful once Karpenter is deployed to provide an untainted landing zone for everything else — see the comment above the taint block in main.tf."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
