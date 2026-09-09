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

variable "enable_vm_public_ip" {
  description = "Whether to create a Public IP and allow inbound SSH to the VM from admin_source_cidr. Defaults to false; the VM is private-only unless explicitly opted in."
  type        = bool
  default     = false
}

variable "admin_source_cidr" {
  description = "Single, explicit source CIDR (e.g. \"203.0.113.10/32\") allowed to SSH to the VM when enable_vm_public_ip is true. Must not be null, empty, \"*\", \"0.0.0.0/0\", or \"Internet\"."
  type        = string
  default     = null

  validation {
    condition = !var.enable_vm_public_ip || (
      can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/(?:[1-9]|[12][0-9]|3[0-2])$", coalesce(var.admin_source_cidr, ""))) &&
      can(cidrhost(coalesce(var.admin_source_cidr, "0.0.0.0/32"), 0))
    )
    error_message = "When enable_vm_public_ip is true, admin_source_cidr must be a specific, valid CIDR block with a prefix length between /1 and /32 (not null, empty, \"*\", \"0.0.0.0/0\", or \"Internet\")."
  }
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
