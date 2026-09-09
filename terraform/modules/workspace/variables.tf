variable "workspace_name" {
  type        = string
  description = "Display name of the Fabric workspace."
}

variable "description" {
  type        = string
  description = "Description shown for the Fabric workspace."
  default     = ""
}

variable "capacity_id" {
  type        = string
  description = "Fabric capacity object GUID to assign the workspace to."
}

variable "skip_capacity_state_validation" {
  type        = bool
  description = "Skip provider capacity-state lookup when the deployment identity cannot enumerate an existing capacity."
  default     = false
}
