variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "capacity_name" {
  type = string
}

variable "sku_name" {
  type    = string
  default = "F2"
}

variable "admin_members" {
  type = list(string)
}

variable "tags" {
  type = map(string)
  default = {
    managedBy = "fabric-as-code"
    iac       = "terraform"
  }
}
