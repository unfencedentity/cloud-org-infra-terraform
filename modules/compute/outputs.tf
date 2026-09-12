output "vm_id" {
  description = "Resource ID of the Linux virtual machine."
  value       = azurerm_linux_virtual_machine.application.id
}

output "vm_name" {
  description = "Name of the Linux virtual machine."
  value       = azurerm_linux_virtual_machine.application.name
}

output "recovery_services_vault_id" {
  description = "ID of the Recovery Services vault protecting the Linux VM."
  value       = azurerm_recovery_services_vault.application.id
}

output "recovery_services_vault_name" {
  description = "Name of the Recovery Services vault protecting the Linux VM."
  value       = azurerm_recovery_services_vault.application.name
}

output "backup_policy_vm_id" {
  description = "ID of the VM backup policy applied to the Linux VM."
  value       = azurerm_backup_policy_vm.application.id
}

output "backup_policy_vm_name" {
  description = "Name of the VM backup policy applied to the Linux VM."
  value       = azurerm_backup_policy_vm.application.name
}

output "backup_protected_vm_id" {
  description = "ID of the protected VM backup registration."
  value       = azurerm_backup_protected_vm.application.id
}
