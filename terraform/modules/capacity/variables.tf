variable "resource_group_name" {
  type        = string
  description = "Name of the Azure resource group that will contain the Fabric capacity."
}

variable "location" {
  type        = string
  description = "Azure region in which to create the Fabric capacity."
}

variable "capacity_name" {
  type        = string
  description = "Globally unique Azure resource name for the Fabric capacity."
}

variable "sku_name" {
  type        = string
  description = "Fabric capacity SKU, such as F2 or F64."
  default     = "F2"
}

variable "admin_members" {
  type        = list(string)
  description = "User principal names or service-principal object IDs that administer the capacity."
}

variable "tags" {
  type        = map(string)
  description = "Azure tags applied to the Fabric capacity resource."
  default = {
    managedBy = "fabric-as-code"
    iac       = "terraform"
  }
}
