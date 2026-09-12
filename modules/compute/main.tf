terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.36"
    }
  }
}

resource "azurerm_linux_virtual_machine" "application" {
  name                            = var.vm_name
  computer_name                   = var.computer_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  network_interface_ids           = [var.network_interface_id]
  size                            = "Standard_B2s_v2"
  admin_username                  = "azureadmin"
  disable_password_authentication = true
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureadmin"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  # Platform-managed boot diagnostics storage; the app storage account has shared-key auth disabled.
  boot_diagnostics {}
}

resource "azurerm_recovery_services_vault" "application" {
  name                = var.recovery_services_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"

  tags = var.tags
}

resource "azurerm_backup_policy_vm" "application" {
  name                = var.backup_policy_name
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.application.name
  timezone            = "UTC"

  backup {
    frequency = "Daily"
    time      = "01:00"
  }

  retention_daily {
    count = 7
  }

  retention_weekly {
    count    = 4
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
}

resource "azurerm_backup_protected_vm" "application" {
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.application.name
  source_vm_id        = azurerm_linux_virtual_machine.application.id
  backup_policy_id    = azurerm_backup_policy_vm.application.id
}
