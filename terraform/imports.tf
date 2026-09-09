# =============================================================================
# imports.tf — conditional item adoption and state-only migration.
#
# In full-platform mode every import is disabled because the workspace and its
# items are new. In existing-workspace mode, a non-empty *_id imports that item;
# a null or empty ID leaves the items module to create it. Fabric import IDs use
# <workspace-id>/<item-id>, after which normal configuration manages the item.
# =============================================================================
import {
  for_each = !var.provision_platform && var.manage_workspaces && try(trimspace(var.workspace_id), "") != "" ? toset([var.workspace_id]) : toset([])
  to       = module.workspace[0].fabric_workspace.this
  id       = each.value
}

import {
  for_each = !var.provision_platform && var.manage_workspaces && try(trimspace(var.git_workspace_id), "") != "" ? toset([var.git_workspace_id]) : toset([])
  to       = module.git_workspace[0].fabric_workspace.this
  id       = each.value
}

import {
  for_each = var.provision_platform || try(trimspace(var.lakehouse_id), "") == "" ? toset([]) : toset([var.lakehouse_id])
  to       = module.items.fabric_lakehouse.this
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.provision_platform || try(trimspace(var.warehouse_id), "") == "" ? toset([]) : toset([var.warehouse_id])
  to       = module.items.fabric_warehouse.this
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.provision_platform || try(trimspace(var.notebook_id), "") == "" ? toset([]) : toset([var.notebook_id])
  to       = module.items.fabric_notebook.this
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.item_deployment_profile == "p0" || var.provision_platform || try(trimspace(var.pipeline_id), "") == "" ? toset([]) : toset([var.pipeline_id])
  to       = module.items.fabric_data_pipeline.this[0]
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.item_deployment_profile == "p0" || var.provision_platform || try(trimspace(var.environment_id), "") == "" ? toset([]) : toset([var.environment_id])
  to       = module.items.fabric_environment.this[0]
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.item_deployment_profile == "p0" || var.provision_platform || try(trimspace(var.eventhouse_id), "") == "" ? toset([]) : toset([var.eventhouse_id])
  to       = module.items.fabric_eventhouse.this[0]
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.item_deployment_profile == "p0" || var.provision_platform || try(trimspace(var.kql_database_id), "") == "" ? toset([]) : toset([var.kql_database_id])
  to       = module.items.fabric_kql_database.this[0]
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.item_deployment_profile == "p0" || var.provision_platform || try(trimspace(var.variable_library_id), "") == "" ? toset([]) : toset([var.variable_library_id])
  to       = module.items.fabric_variable_library.this[0]
  id       = "${local.cicd_workspace_id}/${each.value}"
}

import {
  for_each = var.item_deployment_profile == "p0" || var.provision_platform || try(trimspace(var.ml_experiment_id), "") == "" ? toset([]) : toset([var.ml_experiment_id])
  to       = module.items.fabric_ml_experiment.this[0]
  id       = "${local.cicd_workspace_id}/${each.value}"
}

# The former null_resource represented only execution history, not a remote
# object. Forget it without running a destroy provisioner during upgrades.
removed {
  from = module.sql.null_resource.stored_procs

  lifecycle {
    destroy = false
  }
}