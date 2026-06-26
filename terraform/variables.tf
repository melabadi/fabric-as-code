# =============================================================================
# variables.tf — root inputs. Mirrors the keys in ../.env so the Terraform and
# script paths stay consistent. Provide values via terraform.tfvars (git-ignored).
# =============================================================================

variable "tenant_id" {
  type        = string
  description = "Entra ID (Azure AD) tenant that owns the subscription and capacity."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription where the Fabric capacity is created."
}

variable "resource_group" {
  type        = string
  description = "Resource group for the Fabric capacity."
  default     = "rg-fabric-as-code"
}

variable "location" {
  type        = string
  description = "Azure region (must support Fabric)."
  default     = "westus3"
}

variable "capacity_name" {
  type        = string
  description = "Globally unique Fabric capacity name (lowercase letters/numbers, 3-63 chars)."
}

variable "capacity_sku" {
  type        = string
  description = "Fabric SKU (F2..F2048). F2 is the smallest."
  default     = "F2"

  validation {
    condition     = can(regex("^F(2|4|8|16|32|64|128|256|512|1024|2048)$", var.capacity_sku))
    error_message = "capacity_sku must be one of F2, F4, F8, ... F2048."
  }
}

variable "capacity_admins" {
  type        = list(string)
  description = "Capacity administrators: user UPNs and/or service principal object IDs."
}

variable "workspace_name" {
  type        = string
  description = "Display name of the Fabric workspace."
  default     = "Fabric-as-Code Demo"
}

variable "workspace_description" {
  type        = string
  description = "Workspace description."
  default     = "Workspace provisioned end-to-end by the fabric-as-code repo (Terraform)."
}

variable "lakehouse_name" {
  type    = string
  default = "lh_demo"
}

variable "warehouse_name" {
  type    = string
  default = "wh_demo"
}

variable "notebook_name" {
  type    = string
  default = "nb_demo_load"
}

variable "pipeline_name" {
  type    = string
  default = "pl_demo_ingest"
}

variable "deploy_stored_procedures" {
  type        = bool
  description = "Whether to deploy the Warehouse schema/tables/stored procedures (needs pwsh + az)."
  default     = true
}
