output "lakehouse_id" {
  description = "Fabric GUID of the managed Lakehouse."
  value       = fabric_lakehouse.this.id
}

output "warehouse_id" {
  description = "Fabric GUID of the managed Warehouse."
  value       = fabric_warehouse.this.id
}

output "warehouse_connection_string" {
  description = "SQL endpoint exposed by the Warehouse and consumed by the SQL deployment module."
  value       = fabric_warehouse.this.properties.connection_string
}

output "notebook_id" {
  description = "Fabric GUID of the managed Notebook."
  value       = fabric_notebook.this.id
}

output "pipeline_id" {
  description = "Fabric GUID of the managed Data Pipeline, or null in the P0 profile."
  value       = try(fabric_data_pipeline.this[0].id, null)
}

output "environment_id" {
  description = "Fabric GUID of the managed Spark Environment, or null in the P0 profile."
  value       = try(fabric_environment.this[0].id, null)
}

output "eventhouse_id" {
  description = "Fabric GUID of the managed Eventhouse, or null in the P0 profile."
  value       = try(fabric_eventhouse.this[0].id, null)
}

output "kql_database_id" {
  description = "Fabric GUID of the managed KQL Database, or null in the P0 profile."
  value       = try(fabric_kql_database.this[0].id, null)
}

output "variable_library_id" {
  description = "Fabric GUID of the managed Variable Library, or null in the P0 profile."
  value       = try(fabric_variable_library.this[0].id, null)
}

output "ml_experiment_id" {
  description = "Fabric GUID of the managed ML Experiment, or null in the P0 profile."
  value       = try(fabric_ml_experiment.this[0].id, null)
}

output "extended_item_resource_count" {
  description = "Number of extended Fabric item resources selected by the deployment profile."
  value = (
    length(fabric_data_pipeline.this) +
    length(fabric_environment.this) +
    length(fabric_eventhouse.this) +
    length(fabric_kql_database.this) +
    length(fabric_variable_library.this) +
    length(fabric_ml_experiment.this)
  )
}
