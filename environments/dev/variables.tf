variable "resource_group_name" {
  description = "The name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed."
  type        = string
}

variable "ssh_public_key" {
  description = "The public SSH key used for the Linux VM admin account."
  type        = string
}
