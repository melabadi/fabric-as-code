# =============================================================================
# outputs.tf — useful identifiers after apply.
# =============================================================================

output "capacity_resource_id" {
  description = "ARM resource ID of the Fabric capacity."
  value       = module.capacity.capacity_resource_id
}

output "capacity_guid" {
  description = "Fabric capacity object GUID (used to assign workspaces)."
  value       = module.capacity.capacity_guid
}

output "workspace_id" {
  description = "Fabric workspace GUID."
  value       = module.workspace.workspace_id
}

output "lakehouse_id" {
  value = module.items.lakehouse_id
}

output "warehouse_id" {
  value = module.items.warehouse_id
}

output "notebook_id" {
  value = module.items.notebook_id
}

output "pipeline_id" {
  value = module.items.pipeline_id
}
