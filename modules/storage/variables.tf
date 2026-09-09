variable "resource_group_name" {
  description = "Name of the resource group where storage resources are created."
  type        = string
}

variable "location" {
  description = "Azure region for storage resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to storage resources."
  type        = map(string)
}

variable "storage_account_name" {
  description = "Globally-unique name of the storage account."
  type        = string
}

variable "vnet_id" {
  description = "ID of the virtual network to link the private DNS zone to."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "ID of the subnet used for the storage account's private endpoint."
  type        = string
}

variable "private_endpoint_name" {
  description = "Name of the storage account's blob private endpoint."
  type        = string
}

variable "private_service_connection_name" {
  description = "Name of the private endpoint's private service connection."
  type        = string
}

variable "dns_link_name" {
  description = "Name of the private DNS zone virtual network link."
  type        = string
}
