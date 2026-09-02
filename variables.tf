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
