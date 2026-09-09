output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.application.name
}

output "private_dns_zone_id" {
  description = "Resource ID of the blob private DNS zone."
  value       = azurerm_private_dns_zone.blob.id
}

output "private_endpoint_id" {
  description = "Resource ID of the storage account's blob private endpoint."
  value       = azurerm_private_endpoint.blob.id
}
