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
