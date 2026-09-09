variable "workspace_id" {
  type        = string
  description = "Fabric workspace GUID in which all items are managed."
}

variable "deploy_extended_items" {
  type        = bool
  description = "Create the six extended demo items in addition to the P0 Lakehouse, Warehouse, and Notebook."
  default     = true
}

variable "lakehouse_name" {
  type        = string
  description = "Display name of the managed Lakehouse."
}

variable "warehouse_name" {
  type        = string
  description = "Display name of the managed Warehouse."
}

variable "notebook_name" {
  type        = string
  description = "Display name of the managed Notebook."
}

variable "pipeline_name" {
  type        = string
  description = "Display name of the managed Data Pipeline."
}

variable "environment_name" {
  type        = string
  description = "Display name of the managed Spark Environment."
}

variable "eventhouse_name" {
  type        = string
  description = "Display name of the managed Eventhouse."
}

variable "kql_database_name" {
  type        = string
  description = "Display name of the managed writable KQL Database."
}

variable "variable_library_name" {
  type        = string
  description = "Display name of the managed Variable Library."
}

variable "ml_experiment_name" {
  type        = string
  description = "Display name of the managed ML Experiment."
}

variable "fabric_git_dir" {
  type        = string
  description = "Path to the canonical Fabric Git-native item definition folder."
}
