variable "resource_group_name" {
  description = "Name of the resource group where compute resources are created."
  type        = string
}

variable "location" {
  description = "Azure region for compute resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to compute resources."
  type        = map(string)
}

variable "vm_name" {
  description = "Name of the Linux virtual machine."
  type        = string
}

variable "computer_name" {
  description = "Guest OS computer name of the Linux virtual machine (hyphen-free)."
  type        = string
}

variable "network_interface_id" {
  description = "Resource ID of the network interface attached to the VM."
  type        = string
}

variable "identity_id" {
  description = "Resource ID of the user-assigned managed identity attached to the VM."
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key used for the Linux VM admin account."
  type        = string
}

variable "recovery_services_vault_name" {
  description = "Name of the Recovery Services vault protecting the VM."
  type        = string
}

variable "backup_policy_name" {
  description = "Name of the VM backup policy."
  type        = string
}
