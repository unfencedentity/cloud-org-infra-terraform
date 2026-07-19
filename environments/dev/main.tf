resource "azurerm_resource_group" "core" {
  name     = var.resource_group_name
  location = var.location
}

data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network" "core" {
  name                = "vnet-dev-core-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "application" {
  name                 = "snet-app-dev-weu-001"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.core.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private_endpoint" {
  name                 = "snet-pe-dev-weu-001"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.core.name
  address_prefixes     = ["10.0.2.0/24"]

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_network_security_group" "application" {
  name                = "nsg-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
}

resource "azurerm_subnet_network_security_group_association" "application" {
  subnet_id                 = azurerm_subnet.application.id
  network_security_group_id = azurerm_network_security_group.application.id
}

resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "allow-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.core.name
  network_security_group_name = azurerm_network_security_group.application.name
}

resource "azurerm_public_ip" "application" {
  name                = "pip-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "application" {
  name                = "nic-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name

  ip_configuration {
    name                          = "ipconfig-app-dev-weu-001"
    subnet_id                     = azurerm_subnet.application.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.application.id
  }
}

resource "azurerm_user_assigned_identity" "application" {
  name                = "id-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
}

resource "azurerm_key_vault" "application" {
  name                       = "kv-app-dev-weu-001"
  location                   = azurerm_resource_group.core.location
  resource_group_name        = azurerm_resource_group.core.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

resource "azurerm_key_vault_secret" "application" {
  name         = "test-secret"
  value        = "test-secret-value"
  key_vault_id = azurerm_key_vault.application.id

  depends_on = [
    azurerm_role_assignment.key_vault_secrets_user,
    azurerm_role_assignment.key_vault_secrets_admin,
  ]
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = azurerm_key_vault.application.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.application.principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_admin" {
  scope                = azurerm_key_vault.application.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_account" "application" {
  name                            = "stappdevweu001"
  resource_group_name             = azurerm_resource_group.core.name
  location                        = azurerm_resource_group.core.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  shared_access_key_enabled       = true
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.core.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-dns-link"
  resource_group_name   = azurerm_resource_group.core.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.core.id
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pep-stappdevweu001-blob"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  subnet_id           = azurerm_subnet.private_endpoint.id

  private_service_connection {
    name                           = "psc-stappdevweu001-blob"
    private_connection_resource_id = azurerm_storage_account.application.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_log_analytics_workspace" "application" {
  name                = "log-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "application" {
  name                = "appi-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  workspace_id        = azurerm_log_analytics_workspace.application.id
  application_type    = "web"
}

resource "azurerm_linux_virtual_machine" "application" {
  name                            = "vm-app-dev-weu-001"
  computer_name                   = "vmappdev001"
  location                        = azurerm_resource_group.core.location
  resource_group_name             = azurerm_resource_group.core.name
  network_interface_ids           = [azurerm_network_interface.application.id]
  size                            = "Standard_B2s_v2"
  admin_username                  = "azureadmin"
  disable_password_authentication = true

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
    identity_ids = [azurerm_user_assigned_identity.application.id]
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.application.primary_blob_endpoint
  }
}

resource "azurerm_recovery_services_vault" "application" {
  name                = "rsv-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"

  tags = {
    environment = "dev"
    project     = "core"
    managed_by  = "terraform"
  }
}

resource "azurerm_backup_policy_vm" "application" {
  name                = "bkp-vm-app-dev-weu-001"
  resource_group_name = azurerm_resource_group.core.name
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
  resource_group_name = azurerm_resource_group.core.name
  recovery_vault_name = azurerm_recovery_services_vault.application.name
  source_vm_id        = azurerm_linux_virtual_machine.application.id
  backup_policy_id    = azurerm_backup_policy_vm.application.id
}

resource "azurerm_monitor_diagnostic_setting" "vm" {
  name                       = "diag-vm-app-dev-weu-001"
  target_resource_id         = azurerm_linux_virtual_machine.application.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.application.id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  name                       = "diag-nsg-app-dev-weu-001"
  target_resource_id         = azurerm_network_security_group.application.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.application.id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-kv-app-dev-weu-001"
  target_resource_id         = azurerm_key_vault.application.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.application.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-stappdevweu001"
  target_resource_id         = azurerm_storage_account.application.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.application.id


  enabled_metric {
    category = "Transaction"
  }
}
