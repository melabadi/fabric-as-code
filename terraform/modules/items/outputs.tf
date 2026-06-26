output "lakehouse_id" {
  value = fabric_lakehouse.this.id
}

output "warehouse_id" {
  value = fabric_warehouse.this.id
}

output "notebook_id" {
  value = fabric_notebook.this.id
}

output "pipeline_id" {
  value = fabric_data_pipeline.this.id
}
