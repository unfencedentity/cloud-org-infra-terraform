variable "resource_group_name" {
  description = "Name of the resource group where observability resources are created."
  type        = string
}

variable "location" {
  description = "Azure region for the Log Analytics workspace and Application Insights (monitoring_location)."
  type        = string
}

variable "tags" {
  description = "Tags applied to the action group."
  type        = map(string)
}

variable "monitoring_tags" {
  description = "Tags applied to the Log Analytics workspace and Application Insights."
  type        = map(string)
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace."
  type        = string
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance."
  type        = string
}

variable "action_group_name" {
  description = "Name of the Azure Monitor action group."
  type        = string
}

variable "action_group_short_name" {
  description = "Short name (<=12 chars) of the Azure Monitor action group."
  type        = string
}

variable "alert_email_address" {
  description = "Email address used for Azure Monitor incident notifications."
  type        = string
  sensitive   = true
}
