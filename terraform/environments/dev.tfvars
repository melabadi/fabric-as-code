# =============================================================================
# Public development environment template.
#
# Replace every placeholder, then remove the deployment marker. Pull requests
# validate template files, while trusted deployment workflows skip them.
# deployment: template
# =============================================================================
tenant_id       = "00000000-0000-0000-0000-000000000000"
subscription_id = "00000000-0000-0000-0000-000000000000"

provision_platform      = true
manage_workspaces       = false
deployment_environment  = "dev"
item_deployment_profile = "all"

resource_group  = "rg-replace-fabric-dev"
location        = "westeurope"
capacity_name   = "replacewithuniquefabricdev"
capacity_sku    = "F2"
capacity_admins = ["fabric-admins@example.com"]

workspace_name            = "Replace Fabric Dev CI-CD"
workspace_description     = "Development workspace managed by Terraform."
git_workspace_name        = "Replace Fabric Dev Git"
git_workspace_description = "Development authoring workspace connected to the repository."

# Add real principal object IDs only in a populated environment file.
workspace_role_assignments = {}

# CMK requires item_deployment_profile = "p0" plus the documented tenant,
# service-principal, Key Vault, and key-permission prerequisites.
workspace_encryption = {}

workspace_security_monitoring_enabled = true

# Create and share the Fabric Git connection first, then replace null with the
# configuration shown in terraform/environments/p0.tfvars.example.
git_integration = null

lakehouse_name        = "lh_demo"
warehouse_name        = "wh_demo"
notebook_name         = "nb_demo_load"
pipeline_name         = "pl_demo_ingest"
environment_name      = "env_demo_spark"
eventhouse_name       = "eh_demo_events"
kql_database_name     = "kqldb_demo_events"
variable_library_name = "vl_demo_config"
ml_experiment_name    = "mlexp_demo_forecast"

deploy_stored_procedures     = true
fabric_workspace_firewall_ip = null
