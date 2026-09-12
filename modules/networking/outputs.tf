output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.core.id
}

output "app_subnet_id" {
  description = "ID of the application subnet."
  value       = azurerm_subnet.application.id
}

output "private_endpoint_subnet_id" {
  description = "ID of the private endpoint subnet."
  value       = azurerm_subnet.private_endpoint.id
}

output "appservice_integration_subnet_id" {
  description = "ID of the App Service VNet integration subnet."
  value       = azurerm_subnet.appservice_integration.id
}

output "nsg_id" {
  description = "ID of the application network security group."
  value       = azurerm_network_security_group.application.id
}

output "network_interface_id" {
  description = "ID of the VM's network interface."
  value       = azurerm_network_interface.application.id
}

output "public_ip_id" {
  description = "ID of the VM's Public IP, or null when create_public_access is false."
  value       = var.create_public_access ? azurerm_public_ip.application[0].id : null
}

output "public_ip_address" {
  description = "IP address of the VM's Public IP, or null when create_public_access is false."
  value       = var.create_public_access ? azurerm_public_ip.application[0].ip_address : null
}
