# =============================================================================
# Production full-platform example.
#
# This file contains non-secret identifiers and desired configuration only.
# Replace placeholders in a private copy or inject values through TF_VAR_* in CI;
# authentication comes from Azure CLI/OIDC, never from this file.
# Use a unique remote state key and globally unique capacity name for this environment.
# deployment: template
# =============================================================================
tenant_id       = "00000000-0000-0000-0000-000000000000"
subscription_id = "00000000-0000-0000-0000-000000000000"

# Create the Azure resource group, capacity, two workspaces, and all Fabric items.
provision_platform        = true
deployment_environment    = "prod"
item_deployment_profile   = "all"
resource_group            = "rg-example-fabric-prod"
location                  = "westeurope"
capacity_name             = "replacewithuniquefabricprod"
capacity_sku              = "F2"
capacity_admins           = ["fabric-admins@contoso.com"]
workspace_name            = "Fabric-as-Code Prod CI-CD"
workspace_description     = "Production workspace deployed by the fabric-as-code CI/CD pipeline."
git_workspace_name        = "Fabric-as-Code Prod Git"
git_workspace_description = "Production authoring workspace connected to the repository."

# Environment-specific display names prevent accidental cross-environment reuse.
lakehouse_name        = "lh_sales_prod"
warehouse_name        = "wh_sales_prod"
notebook_name         = "nb_load_sales_prod"
pipeline_name         = "pl_ingest_sales_prod"
environment_name      = "env_spark_prod"
eventhouse_name       = "eh_events_prod"
kql_database_name     = "kqldb_events_prod"
variable_library_name = "vl_config_prod"
ml_experiment_name    = "mlexp_forecast_prod"

# Execute the ordered files under fabric-git/sql after the Warehouse exists.
deploy_stored_procedures = true

# CI supplies this from the runner-network firewall output.
# fabric_workspace_firewall_ip = "<firewall-public-ip>"