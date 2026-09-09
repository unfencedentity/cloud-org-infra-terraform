variable "resource_group_name" {
  description = "Name of the resource group where networking resources are created."
  type        = string
}

variable "location" {
  description = "Azure region for networking resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to networking resources."
  type        = map(string)
}

variable "vnet_name" {
  description = "Name of the virtual network."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
}

variable "app_subnet_name" {
  description = "Name of the application subnet."
  type        = string
}

variable "app_subnet_address_prefixes" {
  description = "Address prefixes for the application subnet."
  type        = list(string)
}

variable "private_endpoint_subnet_name" {
  description = "Name of the private endpoint subnet."
  type        = string
}

variable "private_endpoint_subnet_address_prefixes" {
  description = "Address prefixes for the private endpoint subnet."
  type        = list(string)
}

variable "appservice_integration_subnet_name" {
  description = "Name of the App Service VNet integration subnet."
  type        = string
}

variable "appservice_integration_subnet_address_prefixes" {
  description = "Address prefixes for the App Service VNet integration subnet."
  type        = list(string)
}

variable "nsg_name" {
  description = "Name of the network security group attached to the application subnet."
  type        = string
}

variable "create_public_access" {
  description = "Whether to create the VM Public IP and the inbound SSH NSG rule. Defaults to false (private-only)."
  type        = bool
  default     = false
}

variable "admin_source_cidr" {
  description = "Source CIDR allowed to SSH to the VM when create_public_access is true. Validated by the caller before being passed in."
  type        = string
  default     = null
}

variable "public_ip_name" {
  description = "Name of the VM's Public IP, created only when create_public_access is true."
  type        = string
}

variable "network_interface_name" {
  description = "Name of the VM's network interface."
  type        = string
}

variable "ip_configuration_name" {
  description = "Name of the network interface's IP configuration."
  type        = string
}
