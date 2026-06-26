variable "workspace_id" {
  type = string
}

variable "warehouse_id" {
  type = string
}

variable "warehouse_name" {
  type        = string
  description = "Warehouse display name (= database name)."
}

variable "sql_dir" {
  type        = string
  description = "Folder containing the ordered *.sql files."
}
