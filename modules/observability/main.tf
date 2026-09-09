terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.36"
    }
  }
}

resource "azurerm_log_analytics_workspace" "application" {
  name                = var.log_analytics_workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.monitoring_tags
}

resource "azurerm_application_insights" "application" {
  name                = var.application_insights_name
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.application.id
  application_type    = "web"
  tags                = var.monitoring_tags
}

resource "azurerm_monitor_action_group" "application" {
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name
  enabled             = true

  email_receiver {
    name                    = "ops-email"
    email_address           = var.alert_email_address
    use_common_alert_schema = true
  }

  tags = var.tags
}
