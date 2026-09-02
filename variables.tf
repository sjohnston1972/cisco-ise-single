variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy into. Supply via terraform.tfvars or the ARM_SUBSCRIPTION_ID environment variable (read automatically by the azurerm provider)."
}

variable "resource_group_name" {
  type    = string
  default = "rg-dev-smp-uks-ise"
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "dc_admin_password" {
  type      = string
  sensitive = true

  validation {
    # Azure Windows VM passwords must be 12-123 characters and satisfy at
    # least 3 of: uppercase, lowercase, digit, special character.
    condition = (
      length(var.dc_admin_password) >= 12 &&
      length(var.dc_admin_password) <= 123 &&
      (
        (can(regex("[A-Z]", var.dc_admin_password)) ? 1 : 0) +
        (can(regex("[a-z]", var.dc_admin_password)) ? 1 : 0) +
        (can(regex("[0-9]", var.dc_admin_password)) ? 1 : 0) +
        (can(regex("[^A-Za-z0-9]", var.dc_admin_password)) ? 1 : 0)
      ) >= 3
    )
    error_message = "dc_admin_password must be 12-123 characters and contain at least 3 of: uppercase letter, lowercase letter, digit, special character (Azure Windows VM complexity requirements)."
  }
}

variable "c8kv_admin_password" {
  type      = string
  sensitive = true

  validation {
    # Azure Linux VM passwords must be 12-72 characters, satisfy at least
    # 3 of: uppercase, lowercase, digit, special character, and must not
    # contain the admin username ("ciscoadmin").
    condition = (
      length(var.c8kv_admin_password) >= 12 &&
      length(var.c8kv_admin_password) <= 72 &&
      !can(regex("(?i)ciscoadmin", var.c8kv_admin_password)) &&
      (
        (can(regex("[A-Z]", var.c8kv_admin_password)) ? 1 : 0) +
        (can(regex("[a-z]", var.c8kv_admin_password)) ? 1 : 0) +
        (can(regex("[0-9]", var.c8kv_admin_password)) ? 1 : 0) +
        (can(regex("[^A-Za-z0-9]", var.c8kv_admin_password)) ? 1 : 0)
      ) >= 3
    )
    error_message = "c8kv_admin_password must be 12-72 characters, must not contain the admin username \"ciscoadmin\", and must contain at least 3 of: uppercase letter, lowercase letter, digit, special character (Azure Linux VM complexity requirements)."
  }
}

variable "allowed_inbound_cidr" {
  type        = string
  description = "Source CIDR or Azure service tag permitted inbound to the lab subnet. Widening this to \"*\" (or leaving it empty) re-opens the subnet to the entire Internet -- see the README for the trade-off."
  default     = "VirtualNetwork"

  validation {
    condition     = contains(["VirtualNetwork", "AzureLoadBalancer"], var.allowed_inbound_cidr) || can(cidrhost(var.allowed_inbound_cidr, 0))
    error_message = "allowed_inbound_cidr must be \"VirtualNetwork\", \"AzureLoadBalancer\", or a valid CIDR block (e.g. \"203.0.113.4/32\"). \"*\" and empty strings are not allowed."
  }
}
