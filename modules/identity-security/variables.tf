variable "resource_group_name" {
  description = "Name of the resource group where identity/security resources are created."
  type        = string
}

variable "location" {
  description = "Azure region for identity/security resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to identity/security resources."
  type        = map(string)
}

variable "identity_name" {
  description = "Name of the user-assigned managed identity."
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Key Vault."
  type        = string
}

variable "key_vault_sku_name" {
  description = "Key Vault SKU name."
  type        = string
  default     = "standard"
}

variable "purge_protection_enabled" {
  description = "Whether Key Vault purge protection is enabled."
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Key Vault soft-delete retention period in days."
  type        = number
  default     = 7
}
