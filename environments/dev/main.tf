resource "azurerm_resource_group" "core" {
  name     = local.resource_group_name
  location = var.workload_location
  tags     = local.common_tags
}

data "azurerm_client_config" "current" {}

locals {
  # Application-Environment-Region-Instance naming, matching the cloud-org-infra PowerShell repository convention.
  name_prefix            = "${var.application}-${var.environment}-${var.workload_region_code}-${var.instance_number}"
  monitoring_name_prefix = "${var.application}-${var.environment}-${var.monitoring_region_code}-${var.instance_number}"

  # Hyphen-free variant for resources with strict Azure naming restrictions (Storage Account, Key Vault, VM computer name).
  compact_suffix = lower(replace(local.name_prefix, "-", ""))

  resource_group_name  = "rg-${local.name_prefix}"
  storage_account_name = "st${local.compact_suffix}"

  web_app_name = lower("app-${var.application}-${var.environment}-${var.workload_region_code}-${substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 8)}")

  common_tags = {
    Application = var.application
    Environment = var.environment
    Region      = var.workload_region_code
    ManagedBy   = "Terraform"
  }

  monitoring_tags = merge(local.common_tags, {
    Region = var.monitoring_region_code
  })

  # Belt-and-suspenders gate: only create the SSH rule/Public IP when explicitly enabled with a valid, restricted CIDR.
  vm_public_access_enabled = var.enable_vm_public_ip && (
    can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/(?:[1-9]|[12][0-9]|3[0-2])$", coalesce(var.admin_source_cidr, ""))) &&
    can(cidrhost(coalesce(var.admin_source_cidr, "0.0.0.0/32"), 0))
  )
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.common_tags

  vnet_name          = "vnet-${local.name_prefix}"
  vnet_address_space = ["10.0.0.0/16"]

  app_subnet_name             = "snet-app-${local.name_prefix}"
  app_subnet_address_prefixes = ["10.0.1.0/24"]

  private_endpoint_subnet_name             = "snet-pe-${local.name_prefix}"
  private_endpoint_subnet_address_prefixes = ["10.0.2.0/24"]

  appservice_integration_subnet_name             = "snet-appsvc-${local.name_prefix}"
  appservice_integration_subnet_address_prefixes = ["10.0.3.0/26"]

  nsg_name = "nsg-${local.name_prefix}"

  create_public_access = local.vm_public_access_enabled
  admin_source_cidr    = var.admin_source_cidr

  public_ip_name         = "pip-${local.name_prefix}"
  network_interface_name = "nic-${local.name_prefix}"
  ip_configuration_name  = "ipconfig-${local.name_prefix}"
}

module "identity_security" {
  source = "../../modules/identity-security"

  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.common_tags

  identity_name  = "id-${local.name_prefix}"
  key_vault_name = "kv${local.compact_suffix}"

  key_vault_sku_name         = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}

module "storage" {
  source = "../../modules/storage"

  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.common_tags

  storage_account_name = local.storage_account_name

  vnet_id                    = module.networking.vnet_id
  private_endpoint_subnet_id = module.networking.private_endpoint_subnet_id

  private_endpoint_name           = "pep-blob-${local.name_prefix}"
  private_service_connection_name = "psc-blob-${local.name_prefix}"
  dns_link_name                   = "blob-dns-link"
}

module "observability" {
  source = "../../modules/observability"

  resource_group_name = azurerm_resource_group.core.name
  location            = var.monitoring_location
  tags                = local.common_tags
  monitoring_tags     = local.monitoring_tags

  log_analytics_workspace_name = "log-${local.monitoring_name_prefix}"
  application_insights_name    = "appi-${local.monitoring_name_prefix}"

  action_group_name       = "ag-${local.name_prefix}"
  action_group_short_name = substr("${var.application}${var.environment}", 0, 12)
  alert_email_address     = var.alert_email_address
}

module "compute" {
  source = "../../modules/compute"

  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.common_tags

  vm_name       = "vm-${local.name_prefix}"
  computer_name = "vm${local.compact_suffix}"

  network_interface_id = module.networking.network_interface_id
  identity_id          = module.identity_security.identity_id
  ssh_public_key       = var.ssh_public_key

  recovery_services_vault_name = "rsv-${local.name_prefix}"
  backup_policy_name           = "bkp-vm-${local.name_prefix}"
}

module "application" {
  source = "../../modules/application"

  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.common_tags

  service_plan_name = "asp-${local.name_prefix}"
  web_app_name      = local.web_app_name

  appservice_integration_subnet_id = module.networking.appservice_integration_subnet_id
  identity_id                      = module.identity_security.identity_id
  key_vault_uri                    = module.identity_security.key_vault_uri

  application_insights_connection_string = module.observability.application_insights_connection_string
}

# Cross-cutting alerts and diagnostic settings remain in the environment root rather than in any single
# module: each one targets resources from multiple modules (compute, networking, identity-security, storage,
# application) and routes to the observability module's Log Analytics workspace and action group. Owning them
# in one module would force that module to depend on every other module purely to receive target resource IDs,
# inverting the modules' natural ownership boundaries without eliminating any dependency - only the root
# naturally sees every module's outputs, so wiring them here avoids that circular/reverse-dependency shape.

resource "azurerm_monitor_metric_alert" "vm_high_cpu" {
  name                = "alert-vm-high-cpu-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.core.name
  scopes              = [module.compute.vm_id]
  description         = "Alert when the Linux VM CPU exceeds 80 percent for 15 minutes."
  severity            = 2
  enabled             = true
  window_size         = "PT15M"
  frequency           = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = module.observability.action_group_id
  }

  tags = local.common_tags
}

resource "azurerm_monitor_activity_log_alert" "service_health" {
  name                = "alert-service-health-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.core.name
  location            = "global"
  scopes              = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}"]
  description         = "Alert on Azure Service Health incidents affecting the current subscription."
  enabled             = true

  criteria {
    category = "ServiceHealth"

    service_health {
      locations = [var.workload_location, "Global"]
    }
  }

  action {
    action_group_id = module.observability.action_group_id
  }

  tags = local.common_tags
}

resource "azurerm_monitor_diagnostic_setting" "vm" {
  name                       = "diag-vm-${local.name_prefix}"
  target_resource_id         = module.compute.vm_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  name                       = "diag-nsg-${local.name_prefix}"
  target_resource_id         = module.networking.nsg_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-kv-${local.name_prefix}"
  target_resource_id         = module.identity_security.key_vault_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

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
  name                       = "diag-st-${local.name_prefix}"
  target_resource_id         = module.storage.storage_account_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id


  enabled_metric {
    category = "Transaction"
  }
}

data "azurerm_monitor_diagnostic_categories" "linux_web_app" {
  resource_id = module.application.linux_web_app_id
}

data "azurerm_monitor_diagnostic_categories" "app_service_plan" {
  resource_id = module.application.app_service_plan_id
}

resource "azurerm_monitor_diagnostic_setting" "linux_web_app" {
  name                       = "diag-webapp-${local.name_prefix}"
  target_resource_id         = module.application.linux_web_app_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.linux_web_app.log_category_types
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.linux_web_app.metrics
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "app_service_plan" {
  name                       = "diag-asp-${local.name_prefix}"
  target_resource_id         = module.application.app_service_plan_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.app_service_plan.log_category_types
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.app_service_plan.metrics
    content {
      category = enabled_metric.value
    }
  }
}