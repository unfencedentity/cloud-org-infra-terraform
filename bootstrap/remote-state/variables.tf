variable "location" {
  description = "The Azure region where remote state backend resources are deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for remote state backend resources."
  type        = string
}

variable "state_container_name" {
  description = "Blob container name used for Terraform state."
  type        = string
  default     = "tfstate"
}
