variable "resource_group_name" {
  description = "Name of the resource group where application resources are created."
  type        = string
}

variable "location" {
  description = "Azure region for the App Service plan and Linux Web App."
  type        = string
}

variable "tags" {
  description = "Tags applied to application resources."
  type        = map(string)
}

variable "service_plan_name" {
  description = "Name of the Linux App Service plan."
  type        = string
}

variable "web_app_name" {
  description = "Globally-unique name of the Linux Web App."
  type        = string
}

variable "appservice_integration_subnet_id" {
  description = "ID of the subnet used for the Web App's VNet integration."
  type        = string
}

variable "identity_id" {
  description = "Resource ID of the user-assigned managed identity attached to the Web App."
  type        = string
}

variable "key_vault_uri" {
  description = "Key Vault URI exposed to the app as a non-secret setting."
  type        = string
}

variable "application_insights_connection_string" {
  description = "Application Insights connection string exposed to the app."
  type        = string
  sensitive   = true
}
