variable "application" {
  description = "Short application/workload identifier used to build resource names and tags (e.g. \"core\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.application))
    error_message = "application must be 1-10 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Short environment identifier used to build resource names and tags (e.g. \"dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,6}$", var.environment))
    error_message = "environment must be 1-6 lowercase alphanumeric characters."
  }
}

variable "workload_location" {
  description = "Azure region display name where workload resources are deployed (e.g. \"denmarkeast\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.workload_location))
    error_message = "workload_location must be a lowercase Azure region name with no spaces."
  }
}

variable "workload_region_code" {
  description = "Short 3-letter region code matching workload_location, used in resource names (e.g. \"deu\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}$", var.workload_region_code))
    error_message = "workload_region_code must be exactly 3 lowercase letters."
  }
}

variable "monitoring_location" {
  description = "Azure region display name where monitoring resources are deployed (e.g. \"swedencentral\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.monitoring_location))
    error_message = "monitoring_location must be a lowercase Azure region name with no spaces."
  }
}

variable "monitoring_region_code" {
  description = "Short 3-letter region code matching monitoring_location, used in resource names (e.g. \"swe\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}$", var.monitoring_region_code))
    error_message = "monitoring_region_code must be exactly 3 lowercase letters."
  }
}

variable "instance_number" {
  description = "Zero-padded 3-digit instance number used in resource names (e.g. \"001\")."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{3}$", var.instance_number))
    error_message = "instance_number must be exactly 3 digits."
  }
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
