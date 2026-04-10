variable "resource_group_name" {
  type    = string
  default = "rg-dev-smp-uks-idm"
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "ise_password" {
  type      = string
  sensitive = true
}
