output "app_service_plan_id" {
  description = "ID of the Linux App Service plan."
  value       = azurerm_service_plan.application.id
}

output "app_service_plan_name" {
  description = "Name of the Linux App Service plan."
  value       = azurerm_service_plan.application.name
}

output "linux_web_app_id" {
  description = "ID of the Linux Web App."
  value       = azurerm_linux_web_app.application.id
}

output "linux_web_app_name" {
  description = "Name of the Linux Web App."
  value       = azurerm_linux_web_app.application.name
}

output "linux_web_app_default_hostname" {
  description = "Default hostname of the Linux Web App."
  value       = azurerm_linux_web_app.application.default_hostname
}
