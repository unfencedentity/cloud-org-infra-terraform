output "identity_id" {
  description = "Resource ID of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.application.id
}

output "identity_principal_id" {
  description = "Principal (object) ID of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.application.principal_id
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.application.id
}

output "key_vault_uri" {
  description = "Vault URI of the Key Vault (non-secret; safe to use as an app setting)."
  value       = azurerm_key_vault.application.vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.application.name
}
