variable "workspace_name" {
  type = string
}

variable "description" {
  type    = string
  default = ""
}

variable "capacity_id" {
  type        = string
  description = "Fabric capacity object GUID to assign the workspace to."
}
