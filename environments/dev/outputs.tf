output "recovery_services_vault_name" {
  description = "Name of the Recovery Services Vault protecting the Linux VM."
  value       = module.compute.recovery_services_vault_name
}

output "recovery_services_vault_id" {
  description = "ID of the Recovery Services Vault protecting the Linux VM."
  value       = module.compute.recovery_services_vault_id
}

output "backup_policy_vm_name" {
  description = "Name of the VM backup policy applied to the Linux VM."
  value       = module.compute.backup_policy_vm_name
}

output "backup_policy_vm_id" {
  description = "ID of the VM backup policy applied to the Linux VM."
  value       = module.compute.backup_policy_vm_id
}

output "backup_protected_vm_id" {
  description = "ID of the protected VM backup registration."
  value       = module.compute.backup_protected_vm_id
}

output "action_group_name" {
  description = "Name of the Azure Monitor Action Group used for alert notifications."
  value       = module.observability.action_group_name
}

output "action_group_id" {
  description = "ID of the Azure Monitor Action Group used for alert notifications."
  value       = module.observability.action_group_id
}

output "vm_high_cpu_alert_name" {
  description = "Name of the Linux VM high CPU metric alert."
  value       = azurerm_monitor_metric_alert.vm_high_cpu.name
}

output "vm_high_cpu_alert_id" {
  description = "ID of the Linux VM high CPU metric alert."
  value       = azurerm_monitor_metric_alert.vm_high_cpu.id
}

output "service_health_alert_name" {
  description = "Name of the Azure Service Health activity log alert."
  value       = azurerm_monitor_activity_log_alert.service_health.name
}

output "service_health_alert_id" {
  description = "ID of the Azure Service Health activity log alert."
  value       = azurerm_monitor_activity_log_alert.service_health.id
}

output "app_service_plan_name" {
  description = "Name of the Linux App Service plan."
  value       = module.application.app_service_plan_name
}

output "app_service_plan_id" {
  description = "ID of the Linux App Service plan."
  value       = module.application.app_service_plan_id
}

output "linux_web_app_name" {
  description = "Name of the Linux Web App."
  value       = module.application.linux_web_app_name
}

output "linux_web_app_id" {
  description = "ID of the Linux Web App."
  value       = module.application.linux_web_app_id
}

output "linux_web_app_default_hostname" {
  description = "Default hostname of the Linux Web App."
  value       = module.application.linux_web_app_default_hostname
}

output "linux_web_app_https_url" {
  description = "HTTPS URL of the Linux Web App."
  value       = "https://${module.application.linux_web_app_default_hostname}"
}

output "app_service_integration_subnet_id" {
  description = "ID of the App Service VNet integration subnet."
  value       = module.networking.appservice_integration_subnet_id
}

output "linux_web_app_user_assigned_identity_id" {
  description = "Attached User Assigned Managed Identity resource ID for the Linux Web App."
  value       = module.identity_security.identity_id
}

output "vm_public_ip_address" {
  description = "Public IP address assigned to the VM's network interface, or null when public access is disabled (the default)."
  value       = module.networking.public_ip_address
}

output "vm_public_ip_id" {
  description = "Resource ID of the VM's Public IP, or null when public access is disabled (the default)."
  value       = module.networking.public_ip_id
}