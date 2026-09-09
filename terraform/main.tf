# =============================================================================
# main.tf — optionally creates the platform, then deploys Fabric content.
# Guided walkthrough: ../docs/deployment/README.md
# =============================================================================

# ---- Optional Azure/Fabric platform ----------------------------------------
# Full-platform mode owns the resource group, capacity, and both workspaces.
# Existing-platform mode skips those blocks and uses the role-specific IDs below.
# Learn more: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group
resource "azurerm_resource_group" "this" {
  count = var.provision_platform ? 1 : 0

  name     = var.resource_group
  location = var.location
  tags = {
    environment = var.deployment_environment
    managedBy   = "fabric-as-code"
  }
}

# Stage 1: ../docs/deployment/01-capacity.md
module "capacity" {
  source = "./modules/capacity"
  count  = var.provision_platform ? 1 : 0

  resource_group_name = azurerm_resource_group.this[0].name
  location            = var.location
  capacity_name       = var.capacity_name
  sku_name            = var.capacity_sku
  admin_members       = var.capacity_admins
  tags = {
    environment = var.deployment_environment
    managedBy   = "fabric-as-code"
  }
}

locals {
  workspaces_managed    = var.provision_platform || var.manage_workspaces
  workspace_capacity_id = var.provision_platform ? module.capacity[0].capacity_guid : var.fabric_capacity_id
}

# Stage 2: ../docs/deployment/02-workspaces.md
module "workspace" {
  source = "./modules/workspace"
  count  = local.workspaces_managed ? 1 : 0

  workspace_name                 = var.workspace_name
  description                    = var.workspace_description
  capacity_id                    = local.workspace_capacity_id
  skip_capacity_state_validation = !var.provision_platform
}

module "git_workspace" {
  source = "./modules/workspace"
  count  = local.workspaces_managed ? 1 : 0

  workspace_name                 = var.git_workspace_name
  description                    = var.git_workspace_description
  capacity_id                    = local.workspace_capacity_id
  skip_capacity_state_validation = !var.provision_platform
}

# Downstream resources use stable role-specific GUIDs regardless of whether the
# workspaces were created here or supplied by an existing-platform deployment.
locals {
  cicd_workspace_id = local.workspaces_managed ? module.workspace[0].workspace_id : var.workspace_id
  git_workspace_id  = local.workspaces_managed ? module.git_workspace[0].workspace_id : var.git_workspace_id
  workspace_ids = {
    cicd = local.cicd_workspace_id
    git  = local.git_workspace_id
  }
  workspace_role_assignment_targets = {
    for target in flatten([
      for assignment_name, assignment in var.workspace_role_assignments : [
        for workspace_name in assignment.workspaces : {
          key            = "${workspace_name}.${assignment_name}"
          workspace_id   = local.workspace_ids[workspace_name]
          principal_id   = assignment.principal_id
          principal_type = assignment.principal_type
          role           = assignment.role
        }
      ]
    ]) : target.key => target
  }
  workspace_encryption_targets = {
    for workspace_name, policy in var.workspace_encryption : workspace_name => {
      workspace_id   = local.workspace_ids[workspace_name]
      mode           = policy.enabled ? "Assign" : "Reset"
      key_identifier = policy.enabled ? trimsuffix(policy.key_identifier, "/") : ""
    }
  }
  workspace_firewall_enabled = (
    try(trimspace(var.fabric_workspace_firewall_ip), "") != ""
  )
  workspace_firewall_targets = !local.workspace_firewall_enabled ? {} : merge(
    { cicd = local.cicd_workspace_id },
    local.workspaces_managed || try(trimspace(var.git_workspace_id), "") != "" ? { git = local.git_workspace_id } : {}
  )
  workspace_firewall_rule_name = "github-actions-egress"
}

# Stage 3: ../docs/deployment/03-workspace-settings.md
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace_role_assignment
resource "fabric_workspace_role_assignment" "this" {
  for_each = local.workspace_role_assignment_targets

  workspace_id = each.value.workspace_id
  principal = {
    id   = each.value.principal_id
    type = each.value.principal_type
  }
  role = each.value.role
}

# Workspace CMK APIs are GA, but provider 1.12.1 has no encryption resource.
# Keep the public API call in Terraform's graph until the provider adds one.
# Learn more: https://learn.microsoft.com/fabric/security/workspace-customer-managed-keys
resource "terraform_data" "workspace_encryption" {
  for_each = local.workspace_encryption_targets

  triggers_replace = {
    workspace_id   = each.value.workspace_id
    mode           = each.value.mode
    key_identifier = each.value.key_identifier
  }

  provisioner "local-exec" {
    command     = <<-EOT
      & '${path.root}/../scripts/powershell/set-fabric-workspace-encryption.ps1' `
        -WorkspaceId '${each.value.workspace_id}' `
        -Mode '${each.value.mode}' `
        -KeyIdentifier '${each.value.key_identifier}'
    EOT
    interpreter = ["pwsh", "-NoProfile", "-Command"]
  }

  depends_on = [
    fabric_workspace_role_assignment.this,
    terraform_data.workspace_firewall,
  ]
}

# The Fabric provider does not yet expose workspace communication policies.
# This state marker invokes Fabric's documented REST API after each workspace
# exists and before Terraform sends Git or item operations through the provider.
# Learn more: https://learn.microsoft.com/fabric/security/security-workspace-level-firewall-set-up
resource "terraform_data" "workspace_firewall" {
  for_each = local.workspace_firewall_targets

  triggers_replace = {
    workspace_id = each.value
    ip_address   = var.fabric_workspace_firewall_ip
    rule_name    = local.workspace_firewall_rule_name
  }

  provisioner "local-exec" {
    command     = <<-EOT
      & '${path.root}/../scripts/powershell/set-fabric-workspace-firewall.ps1' `
        -WorkspaceId '${each.value}' `
        -IpAddress '${var.fabric_workspace_firewall_ip}' `
        -RuleName '${local.workspace_firewall_rule_name}'
    EOT
    interpreter = ["pwsh", "-NoProfile", "-Command"]
  }
}

# Existing workspaces are reconciled before planning by deploy-terraform.ps1.
# This marker handles the first full-platform apply, when the Git workspace ID
# does not exist until Terraform creates it in the same graph.
# Stage 4: ../docs/deployment/04-git-integration.md
resource "terraform_data" "git_credentials" {
  count = (
    var.git_integration != null &&
    var.git_integration.credentials_source == "ConfiguredConnection"
  ) ? 1 : 0

  triggers_replace = {
    workspace_id  = local.git_workspace_id
    connection_id = var.git_integration.connection_id
  }

  provisioner "local-exec" {
    command     = <<-EOT
      & '${path.root}/../scripts/powershell/set-fabric-git-credentials.ps1' `
        -WorkspaceId '${local.git_workspace_id}' `
        -ConnectionId '${var.git_integration.connection_id}'
    EOT
    interpreter = ["pwsh", "-NoProfile", "-Command"]
  }

  depends_on = [terraform_data.workspace_firewall]
}

# ---- Optional Fabric Git connection ----------------------------------------
# This workspace is an authoring mirror only. Terraform-managed item definitions
# are deployed to the separate CI/CD workspace below.
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace_git
resource "fabric_workspace_git" "this" {
  count = var.git_integration == null ? 0 : 1

  workspace_id = local.git_workspace_id
  git_provider_details = {
    git_provider_type = var.git_integration.provider_type
    organization_name = var.git_integration.organization_name
    project_name      = var.git_integration.project_name
    owner_name        = var.git_integration.owner_name
    repository_name   = var.git_integration.repository_name
    branch_name       = var.git_integration.branch_name
    directory_name    = var.git_integration.directory_name
  }
  git_credentials = {
    source        = var.git_integration.credentials_source
    connection_id = var.git_integration.connection_id
  }
  initialization_strategy = var.git_integration.initialization_strategy
  options = {
    allow_override_items = var.git_integration.allow_override_items
  }

  depends_on = [
    terraform_data.git_credentials,
    terraform_data.workspace_encryption,
    terraform_data.workspace_firewall,
  ]
}

# ---- Fabric workspace content ----------------------------------------------
# The module manages the selected item profile and renders Notebook/Pipeline
# definitions with the environment-specific GUIDs created in this graph.
# Stage 5: ../docs/deployment/05-content-files.md
module "items" {
  source                = "./modules/items"
  workspace_id          = local.cicd_workspace_id
  deploy_extended_items = var.item_deployment_profile == "all"
  lakehouse_name        = var.lakehouse_name
  warehouse_name        = var.warehouse_name
  notebook_name         = var.notebook_name
  pipeline_name         = var.pipeline_name
  environment_name      = var.environment_name
  eventhouse_name       = var.eventhouse_name
  kql_database_name     = var.kql_database_name
  variable_library_name = var.variable_library_name
  ml_experiment_name    = var.ml_experiment_name
  fabric_git_dir        = "${path.root}/../fabric-git"

  depends_on = [
    terraform_data.workspace_encryption,
    terraform_data.workspace_firewall,
  ]
}

# ---- Warehouse data-plane objects ------------------------------------------
# The provider supplies the endpoint; the SQL module obtains an Entra SQL token
# at execution time and reruns only when the Warehouse or SQL source changes.
module "sql" {
  source         = "./modules/sql"
  count          = var.deploy_stored_procedures ? 1 : 0
  warehouse_id   = module.items.warehouse_id
  warehouse_name = var.warehouse_name
  server         = module.items.warehouse_connection_string
  sql_dir        = "${path.root}/../fabric-git/sql"
}
