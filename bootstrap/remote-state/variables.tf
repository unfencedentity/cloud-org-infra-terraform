variable "environment" {
  description = "Short environment identifier of the environment this remote-state backend serves (e.g. \"dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,6}$", var.environment))
    error_message = "environment must be 1-6 lowercase alphanumeric characters."
  }
}

variable "workload_location" {
  description = "Azure region display name where the remote-state backend resources are deployed (e.g. \"denmarkeast\")."
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

variable "instance_number" {
  description = "Zero-padded 3-digit instance number used in resource names (e.g. \"001\")."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{3}$", var.instance_number))
    error_message = "instance_number must be exactly 3 digits."
  }
}

variable "state_container_name" {
  description = "Blob container name used for Terraform state."
  type        = string
  default     = "tfstate"
}
