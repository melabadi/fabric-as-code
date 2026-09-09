# =============================================================================
# deployment_modes.tftest.hcl — mocked plans for mode and input contracts.
#
# Mock providers keep these tests offline: no Azure or Fabric resource is
# created. The runs verify both workspace modes, optional Git configuration, and
# expected failures for each mode's conditionally required inputs.
# =============================================================================
mock_provider "azurerm" {}

mock_provider "fabric" {
  mock_data "fabric_capacity" {
    defaults = {
      id = "00000000-0000-0000-0000-000000000010"
    }
  }
}

# Clear optional IDs so TF_VAR values from a real CI environment cannot leak
# imports or Git settings into these isolated plan tests.
variables {
  workspace_name             = "Fabric-as-Code Test CI/CD"
  git_workspace_name         = "Fabric-as-Code Test Git"
  resource_group             = "rg-example-fabric-test"
  capacity_name              = "fabricascodetest"
  git_workspace_id           = null
  manage_workspaces          = false
  lakehouse_id               = null
  warehouse_id               = null
  notebook_id                = null
  pipeline_id                = null
  environment_id             = null
  eventhouse_id              = null
  kql_database_id            = null
  variable_library_id        = null
  ml_experiment_id           = null
  git_integration            = null
  workspace_role_assignments = {}
  workspace_encryption       = {}
}

run "full_platform" {
  command = plan

  variables {
    tenant_id                    = "00000000-0000-0000-0000-000000000001"
    subscription_id              = "00000000-0000-0000-0000-000000000002"
    provision_platform           = true
    deployment_environment       = "test"
    item_deployment_profile      = "p0"
    resource_group               = "rg-example-fabric-test"
    capacity_name                = "fabricascodetest"
    capacity_admins              = ["admin@contoso.com"]
    workspace_name               = "Fabric-as-Code Test"
    fabric_workspace_firewall_ip = "203.0.113.10"
    deploy_stored_procedures     = false
    lakehouse_id                 = null
    warehouse_id                 = null
    notebook_id                  = null
    pipeline_id                  = null
    environment_id               = null
    eventhouse_id                = null
    kql_database_id              = null
    variable_library_id          = null
    ml_experiment_id             = null
    workspace_role_assignments = {
      platform_admins = {
        workspaces     = ["cicd", "git"]
        principal_id   = "00000000-0000-0000-0000-000000000050"
        principal_type = "Group"
        role           = "Admin"
      }
      cicd_deployers = {
        principal_id   = "00000000-0000-0000-0000-000000000060"
        principal_type = "ServicePrincipal"
        role           = "Contributor"
      }
    }
    workspace_encryption = {
      cicd = {
        key_identifier = "https://fabric-security.vault.azure.net/keys/cicd-data"
      }
      git = {
        key_identifier = "https://fabric-security.vault.azure.net/keys/git-data/"
      }
    }
    git_integration = {
      provider_type   = "GitHub"
      owner_name      = "contoso"
      repository_name = "fabric-as-code"
      branch_name     = "main"
      directory_name  = "/fabric-git"
      connection_id   = "00000000-0000-0000-0000-000000000030"
    }
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 1
    error_message = "Full-platform mode must create one Azure resource group."
  }

  assert {
    condition     = azurerm_resource_group.this[0].tags["environment"] == "test"
    error_message = "Full-platform resources must carry the selected environment tag."
  }

  assert {
    condition     = length(module.workspace) == 1 && length(module.git_workspace) == 1
    error_message = "Full-platform mode must create separate CI/CD and Git workspaces."
  }

  assert {
    condition     = length(terraform_data.workspace_firewall) == 2
    error_message = "Full-platform mode must plan both workspace firewall markers before workspace IDs are known."
  }

  assert {
    condition     = length(terraform_data.git_credentials) == 1 && length(fabric_workspace_git.this) == 1
    error_message = "First-time full-platform Git deployment must plan caller credentials before the Git connection."
  }

  assert {
    condition = (
      length(fabric_workspace_role_assignment.this) == 3 &&
      fabric_workspace_role_assignment.this["cicd.platform_admins"].role == "Admin" &&
      fabric_workspace_role_assignment.this["git.platform_admins"].principal.type == "Group" &&
      fabric_workspace_role_assignment.this["cicd.cicd_deployers"].role == "Contributor"
    )
    error_message = "Workspace policy must expand role assignments across the selected CI/CD and Git workspaces."
  }

  assert {
    condition = (
      length(terraform_data.workspace_encryption) == 2 &&
      terraform_data.workspace_encryption["cicd"].triggers_replace.mode == "Assign" &&
      terraform_data.workspace_encryption["git"].triggers_replace.key_identifier == "https://fabric-security.vault.azure.net/keys/git-data"
    )
    error_message = "Workspace policy must normalize and plan CMK assignment for both managed workspaces."
  }

  assert {
    condition = (
      output.workspace_security_summary.monitoring_enabled &&
      output.workspace_security_summary.role_assignment_count == 3 &&
      length(output.workspace_security_summary.cmk_workspaces) == 2 &&
      contains(output.workspace_security_summary.cmk_workspaces, "cicd") &&
      contains(output.workspace_security_summary.cmk_workspaces, "git") &&
      length(output.workspace_security_summary.firewall_workspaces) == 2 &&
      contains(output.workspace_security_summary.firewall_workspaces, "cicd") &&
      contains(output.workspace_security_summary.firewall_workspaces, "git") &&
      output.workspace_security_summary.native_monitoring_lifecycle == "manual-portal"
    )
    error_message = "The workspace security summary must expose policy, CMK, role assignment, and monitoring configuration."
  }

  assert {
    condition     = output.extended_item_resource_count == 0
    error_message = "The P0 profile must deploy Lakehouse, Warehouse, and Notebook without extended items."
  }

  assert {
    condition = (
      fileexists("${path.root}/../fabric-git/nb_git_authoring_demo.Notebook/notebook-content.py") &&
      fileexists("${path.root}/../fabric-git/pl_git_authoring_demo.DataPipeline/pipeline-content.json") &&
      fileexists("${path.root}/../fabric-git/sql/03-stored-procedures.sql") &&
      length(fileset("${path.root}/../fabric-items", "**")) == 0
    )
    error_message = "fabric-git must be the only Fabric content source, including Warehouse SQL."
  }
}

run "existing_workspace" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    deploy_stored_procedures = false
    lakehouse_id             = null
    warehouse_id             = null
    notebook_id              = null
    pipeline_id              = null
    environment_id           = null
    eventhouse_id            = null
    kql_database_id          = null
    variable_library_id      = null
    ml_experiment_id         = null
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 0
    error_message = "Existing-workspace mode must not create Azure platform resources."
  }

  assert {
    condition     = output.workspace_id == "00000000-0000-0000-0000-000000000020"
    error_message = "Existing-workspace mode must deploy to the supplied workspace ID."
  }

  assert {
    condition     = length(fabric_workspace_git.this) == 0
    error_message = "Git integration must remain disabled unless explicitly configured."
  }
}

run "existing_capacity_manages_both_workspaces" {
  command = plan

  override_resource {
    target = module.workspace[0].fabric_workspace.this
    values = {
      id = "00000000-0000-0000-0000-000000000020"
    }
  }

  override_resource {
    target = module.git_workspace[0].fabric_workspace.this
    values = {
      id = "00000000-0000-0000-0000-000000000040"
    }
  }

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    manage_workspaces        = true
    deployment_environment   = "test"
    capacity_name            = "fabricascodetest"
    fabric_capacity_id       = "00000000-0000-0000-0000-000000000010"
    workspace_name           = "Fabric-as-Code Test CI/CD"
    git_workspace_name       = "Fabric-as-Code Test Git"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    git_workspace_id         = "00000000-0000-0000-0000-000000000040"
    deploy_stored_procedures = false
  }

  assert {
    condition     = length(module.workspace) == 1 && length(module.git_workspace) == 1
    error_message = "Existing-capacity workspace management must own both role-specific workspaces."
  }

  assert {
    condition = (
      output.cicd_workspace_id == module.workspace[0].workspace_id &&
      output.git_workspace_id == module.git_workspace[0].workspace_id &&
      output.cicd_workspace_id != output.git_workspace_id
    )
    error_message = "Managed CI/CD and Git workspace identities must remain distinct."
  }
}

run "existing_workspace_with_git" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    git_workspace_id         = "00000000-0000-0000-0000-000000000040"
    deploy_stored_procedures = false
    git_integration = {
      provider_type   = "GitHub"
      owner_name      = "contoso"
      repository_name = "fabric-as-code"
      branch_name     = "main"
      directory_name  = "/fabric-git"
      connection_id   = "00000000-0000-0000-0000-000000000030"
    }
  }

  assert {
    condition     = fabric_workspace_git.this[0].git_provider_details.git_provider_type == "GitHub"
    error_message = "The workspace Git resource must use the selected provider."
  }

  assert {
    condition     = fabric_workspace_git.this[0].workspace_id == "00000000-0000-0000-0000-000000000040"
    error_message = "Git integration must target the dedicated authoring workspace."
  }

  assert {
    condition     = fabric_workspace_git.this[0].initialization_strategy == "PreferRemote"
    error_message = "The authoring workspace must initialize from the remote repository by default."
  }

  assert {
    condition     = length(terraform_data.git_credentials) == 1
    error_message = "Configured Git integration must bind caller-specific credentials through the Terraform graph."
  }
}

run "existing_workspace_with_git_requires_git_workspace_id" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    git_workspace_id         = null
    deploy_stored_procedures = false
    git_integration = {
      provider_type   = "GitHub"
      owner_name      = "contoso"
      repository_name = "fabric-as-code"
      branch_name     = "main"
      directory_name  = "/fabric-git"
      connection_id   = "00000000-0000-0000-0000-000000000030"
    }
  }

  expect_failures = [var.git_workspace_id]
}

run "existing_workspace_with_git_requires_distinct_workspaces" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    git_workspace_id         = "00000000-0000-0000-0000-000000000020"
    deploy_stored_procedures = false
    git_integration = {
      provider_type   = "GitHub"
      owner_name      = "contoso"
      repository_name = "fabric-as-code"
      branch_name     = "main"
      directory_name  = "/fabric-git"
      connection_id   = "00000000-0000-0000-0000-000000000030"
    }
  }

  expect_failures = [var.git_workspace_id]
}

run "existing_workspaces_apply_deployment_firewall" {
  command = plan

  variables {
    tenant_id                    = "00000000-0000-0000-0000-000000000001"
    subscription_id              = "00000000-0000-0000-0000-000000000002"
    provision_platform           = false
    deployment_environment       = "test"
    workspace_id                 = "00000000-0000-0000-0000-000000000020"
    git_workspace_id             = "00000000-0000-0000-0000-000000000040"
    deploy_stored_procedures     = false
    fabric_workspace_firewall_ip = "203.0.113.10"
  }

  assert {
    condition     = length(terraform_data.workspace_firewall) == 2
    error_message = "The deployment firewall must cover both CI/CD and Git workspaces when both IDs are supplied."
  }

  assert {
    condition = alltrue([
      for marker in terraform_data.workspace_firewall :
      marker.triggers_replace.ip_address == "203.0.113.10"
    ])
    error_message = "Each workspace firewall marker must use the configured stable egress IP."
  }
}

run "workspace_firewall_rejects_invalid_ip" {
  command = plan

  variables {
    tenant_id                    = "00000000-0000-0000-0000-000000000001"
    subscription_id              = "00000000-0000-0000-0000-000000000002"
    provision_platform           = false
    deployment_environment       = "test"
    workspace_id                 = "00000000-0000-0000-0000-000000000020"
    deploy_stored_procedures     = false
    fabric_workspace_firewall_ip = "not-an-ip"
  }

  expect_failures = [var.fabric_workspace_firewall_ip]
}

run "workspace_cmk_rejects_versioned_key" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    item_deployment_profile  = "p0"
    deploy_stored_procedures = false
    workspace_encryption = {
      cicd = {
        key_identifier = "https://fabric-security.vault.azure.net/keys/cicd-data/00000000000000000000000000000000"
      }
    }
  }

  expect_failures = [var.workspace_encryption]
}

run "workspace_cmk_rejects_extended_items" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    item_deployment_profile  = "all"
    deploy_stored_procedures = false
    workspace_encryption = {
      cicd = {
        key_identifier = "https://fabric-security.vault.azure.net/keys/cicd-data"
      }
    }
  }

  expect_failures = [var.workspace_encryption]
}

run "workspace_roles_reject_duplicate_principal" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    deploy_stored_procedures = false
    workspace_role_assignments = {
      first = {
        principal_id   = "00000000-0000-0000-0000-000000000050"
        principal_type = "Group"
        role           = "Admin"
      }
      duplicate = {
        principal_id   = "00000000-0000-0000-0000-000000000050"
        principal_type = "Group"
        role           = "Viewer"
      }
    }
  }

  expect_failures = [var.workspace_role_assignments]
}

run "full_platform_rejects_stale_workspace_ids" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = true
    deployment_environment   = "test"
    capacity_admins          = ["admin@contoso.com"]
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    deploy_stored_procedures = false
  }

  expect_failures = [var.workspace_id]
}

run "full_platform_rejects_stale_git_workspace_id" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = true
    deployment_environment   = "test"
    capacity_admins          = ["admin@contoso.com"]
    workspace_id             = null
    git_workspace_id         = "00000000-0000-0000-0000-000000000040"
    deploy_stored_procedures = false
  }

  expect_failures = [var.git_workspace_id]
}

run "existing_workspace_requires_capacity_arm_identity" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    resource_group           = null
    capacity_name            = null
    workspace_id             = "00000000-0000-0000-0000-000000000020"
    deploy_stored_procedures = false
  }

  expect_failures = [
    var.resource_group,
    var.capacity_name,
  ]
}

run "existing_workspace_requires_id" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = false
    deployment_environment   = "test"
    workspace_id             = null
    deploy_stored_procedures = false
  }

  expect_failures = [var.workspace_id]
}

run "full_platform_requires_capacity_configuration" {
  command = plan

  variables {
    tenant_id                = "00000000-0000-0000-0000-000000000001"
    subscription_id          = "00000000-0000-0000-0000-000000000002"
    provision_platform       = true
    deployment_environment   = "test"
    capacity_name            = null
    capacity_admins          = []
    deploy_stored_procedures = false
  }

  expect_failures = [
    var.capacity_name,
    var.capacity_admins,
  ]
}