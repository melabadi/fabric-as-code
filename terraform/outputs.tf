# =============================================================================
# outputs.tf — managed Fabric identifiers after apply.
# =============================================================================

output "workspace_id" {
  description = "Fabric CI/CD workspace GUID used by the deployment. Retained for compatibility."
  value       = local.cicd_workspace_id
}

output "cicd_workspace_id" {
  description = "Fabric workspace GUID that receives Terraform-managed item deployments."
  value       = local.cicd_workspace_id
}

output "git_workspace_id" {
  description = "Fabric authoring workspace GUID connected to Git, or null when using one existing workspace without Git."
  value       = local.git_workspace_id
}

output "git_connection_state" {
  description = "Fabric Git connection state, or null when Git integration is disabled."
  value       = try(fabric_workspace_git.this[0].git_connection_state, null)
}

output "capacity_resource_id" {
  description = "Azure resource ID of the managed capacity, or null in existing-workspace mode."
  value       = var.provision_platform ? module.capacity[0].capacity_resource_id : null
}

output "deployment_environment" {
  description = "Environment identity used for state and workflow isolation."
  value       = var.deployment_environment
}

output "location" {
  description = "Azure region used by capacity and service-tag validation."
  value       = var.location
}

output "warehouse_name" {
  description = "Display name used for authenticated Warehouse TDS verification."
  value       = var.warehouse_name
}

output "cicd_workspace_cmk_key_identifier" {
  description = "Expected versionless CMK URI for CI/CD monitoring, or null when CMK is reset or unmanaged."
  value = try(
    local.workspace_encryption_targets["cicd"].mode == "Assign"
    ? local.workspace_encryption_targets["cicd"].key_identifier
    : null,
    null
  )
}

output "workspace_security_monitoring_enabled" {
  description = "Whether deployment and scheduled workspace security canaries are enabled."
  value       = var.workspace_security_monitoring_enabled
}

output "workspace_security_summary" {
  description = "Plan-visible summary of workspace policy, CMK, role-assignment, and monitoring configuration."
  value = {
    cmk_workspaces              = sort(keys(local.workspace_encryption_targets))
    firewall_workspaces         = sort(keys(local.workspace_firewall_targets))
    monitoring_enabled          = var.workspace_security_monitoring_enabled
    role_assignment_count       = length(local.workspace_role_assignment_targets)
    native_monitoring_lifecycle = "manual-portal"
  }
}

output "lakehouse_id" {
  description = "Fabric GUID of the managed Lakehouse."
  value       = module.items.lakehouse_id
}

output "warehouse_id" {
  description = "Fabric GUID of the managed Warehouse."
  value       = module.items.warehouse_id
}

output "notebook_id" {
  description = "Fabric GUID of the managed Notebook."
  value       = module.items.notebook_id
}

output "pipeline_id" {
  description = "Fabric GUID of the managed Data Pipeline."
  value       = module.items.pipeline_id
}

output "environment_id" {
  description = "Fabric GUID of the managed Spark Environment."
  value       = module.items.environment_id
}

output "eventhouse_id" {
  description = "Fabric GUID of the managed Eventhouse."
  value       = module.items.eventhouse_id
}

output "kql_database_id" {
  description = "Fabric GUID of the managed KQL Database."
  value       = module.items.kql_database_id
}

output "variable_library_id" {
  description = "Fabric GUID of the managed Variable Library."
  value       = module.items.variable_library_id
}

output "ml_experiment_id" {
  description = "Fabric GUID of the managed ML Experiment."
  value       = module.items.ml_experiment_id
}

output "extended_item_resource_count" {
  description = "Number of extended Fabric item resources selected by the deployment profile."
  value       = module.items.extended_item_resource_count
}
