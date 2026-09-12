terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.36"
    }
  }
}

resource "azurerm_service_plan" "application" {
  name                = var.service_plan_name
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "B1"
  worker_count        = 1

  tags = var.tags
}

resource "azurerm_linux_web_app" "application" {
  name                                           = var.web_app_name
  location                                       = var.location
  resource_group_name                            = var.resource_group_name
  service_plan_id                                = azurerm_service_plan.application.id
  enabled                                        = true
  https_only                                     = true
  public_network_access_enabled                  = true
  client_affinity_enabled                        = false
  virtual_network_subnet_id                      = var.appservice_integration_subnet_id
  key_vault_reference_identity_id                = var.identity_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    http2_enabled                     = true
    remote_debugging_enabled          = false
    health_check_path                 = "/"
    health_check_eviction_time_in_min = 5
    vnet_route_all_enabled            = true

    application_stack {
      python_version = "3.12"
    }
  }

  app_settings = {
    KEY_VAULT_URI                         = var.key_vault_uri
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.application_insights_connection_string
  }

  tags = var.tags
}
