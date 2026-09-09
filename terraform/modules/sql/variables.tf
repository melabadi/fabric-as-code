variable "warehouse_id" {
  type        = string
  description = "Fabric GUID of the Warehouse; changing it forces the deployment marker to be replaced."
}

variable "warehouse_name" {
  type        = string
  description = "Warehouse display name (= database name)."
}

variable "server" {
  type        = string
  description = "Warehouse SQL connection string exposed by the Fabric provider."
}

variable "sql_dir" {
  type        = string
  description = "Folder containing the ordered *.sql files."
}
