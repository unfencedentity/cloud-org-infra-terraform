data "azurerm_client_config" "current" {}

locals {
  storage_account_name = "st${substr(sha1("${data.azurerm_client_config.current.subscription_id}-dev-weu-tfstate"), 0, 22)}"

  common_tags = {
    environment = "dev"
    project     = "core"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "remote_state" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_storage_account" "remote_state" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.remote_state.name
  location                        = azurerm_resource_group.remote_state.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "remote_state" {
  name                  = var.state_container_name
  storage_account_id    = azurerm_storage_account.remote_state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "current_principal_blob_data_contributor" {
  scope                = azurerm_storage_container.remote_state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.current_principal_blob_data_contributor]
  create_duration = "90s"
}

resource "azurerm_management_lock" "remote_state_storage_cannot_delete" {
  name       = "lock-remote-state-storage-cannot-delete"
  scope      = azurerm_storage_account.remote_state.id
  lock_level = "CanNotDelete"
  notes      = "Protect Terraform remote state storage account from accidental deletion."

  depends_on = [time_sleep.wait_for_rbac]
}
