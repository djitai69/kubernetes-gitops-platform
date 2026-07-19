variable "repository_name" {
  type    = string
  default = "node-api"
}

variable "image_tag_mutability" {
  description = "Immutable tags — approved production images must never be overwritten"
  type        = string
  default     = "IMMUTABLE"
}

variable "scan_on_push" {
  type    = bool
  default = true
}

variable "retention_count" {
  description = "How many tagged images to retain, to support rollback"
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
