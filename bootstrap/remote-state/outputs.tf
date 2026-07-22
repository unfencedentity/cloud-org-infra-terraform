output "resource_group_name" {
  description = "Remote state resource group name."
  value       = azurerm_resource_group.remote_state.name
}

output "storage_account_name" {
  description = "Remote state storage account name."
  value       = azurerm_storage_account.remote_state.name
}

output "container_name" {
  description = "Remote state container name."
  value       = azurerm_storage_container.remote_state.name
}
