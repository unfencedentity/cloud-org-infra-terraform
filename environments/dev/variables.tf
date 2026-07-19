variable "resource_group_name" {
  description = "The name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed."
  type        = string
}

variable "ssh_public_key" {
  description = "The public SSH key used for the Linux VM admin account."
  type        = string
}

variable "alert_email_address" {
  description = "Email address used for Azure Monitor incident notifications."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email_address))
    error_message = "alert_email_address must be a non-empty email address."
  }
}
