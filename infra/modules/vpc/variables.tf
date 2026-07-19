variable "name" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  description = "true for non-production (cost trade-off); false for production (one NAT per AZ)"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "EKS cluster name, used for the required subnet discovery tags"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
