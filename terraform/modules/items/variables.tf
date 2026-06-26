variable "workspace_id" {
  type = string
}

variable "lakehouse_name" {
  type = string
}

variable "warehouse_name" {
  type = string
}

variable "notebook_name" {
  type = string
}

variable "pipeline_name" {
  type = string
}

variable "fabric_items_dir" {
  type        = string
  description = "Path to the shared fabric-items definition folder."
}
