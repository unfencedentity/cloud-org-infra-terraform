output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.application.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.application.name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance."
  value       = azurerm_application_insights.application.id
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance."
  value       = azurerm_application_insights.application.connection_string
  sensitive   = true
}

output "action_group_id" {
  description = "Resource ID of the Azure Monitor action group."
  value       = azurerm_monitor_action_group.application.id
}

output "action_group_name" {
  description = "Name of the Azure Monitor action group."
  value       = azurerm_monitor_action_group.application.name
}
