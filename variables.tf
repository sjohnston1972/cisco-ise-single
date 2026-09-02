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
}

variable "c8kv_admin_password" {
  type      = string
  sensitive = true
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
