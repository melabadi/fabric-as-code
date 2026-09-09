# =============================================================================
# modules/items — nine managed Fabric workspace items.
#
# Lakehouse, Notebook, and Pipeline consume the native definitions committed by
# Fabric Git. Terraform renders only target-specific runtime IDs in memory.
# Deployment guide: ../../../docs/deployment/05-content-files.md
# =============================================================================
terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

locals {
  lakehouse_source_dir = "${var.fabric_git_dir}/lh_git_authoring_demo.Lakehouse"
  notebook_source_dir  = "${var.fabric_git_dir}/nb_git_authoring_demo.Notebook"
  pipeline_source_dir  = "${var.fabric_git_dir}/pl_git_authoring_demo.DataPipeline"

  notebook_platform          = jsondecode(file("${local.notebook_source_dir}/.platform"))
  source_notebook_logical_id = local.notebook_platform.config.logicalId
  neutral_workspace_id       = "00000000-0000-0000-0000-000000000000"
}

# ---- Lakehouse (auto-creates a SQL analytics endpoint) ----------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/lakehouse
resource "fabric_lakehouse" "this" {
  workspace_id              = var.workspace_id
  display_name              = var.lakehouse_name
  format                    = "Default"
  definition_update_enabled = true

  definition = {
    "alm.settings.json" = {
      source          = "${local.lakehouse_source_dir}/alm.settings.json"
      processing_mode = "None"
    }
    "lakehouse.metadata.json" = {
      source          = "${local.lakehouse_source_dir}/lakehouse.metadata.json"
      processing_mode = "None"
    }
    "shortcuts.metadata.json" = {
      source          = "${local.lakehouse_source_dir}/shortcuts.metadata.json"
      processing_mode = "None"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---- Warehouse --------------------------------------------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/warehouse
resource "fabric_warehouse" "this" {
  workspace_id = var.workspace_id
  display_name = var.warehouse_name

  lifecycle {
    prevent_destroy = true
  }
}

# ---- Environment ------------------------------------------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/environment
resource "fabric_environment" "this" {
  count = var.deploy_extended_items ? 1 : 0

  workspace_id = var.workspace_id
  display_name = var.environment_name
  description  = "Spark environment managed by Terraform."

  lifecycle {
    prevent_destroy = true
  }
}

# ---- Eventhouse -------------------------------------------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/eventhouse
resource "fabric_eventhouse" "this" {
  count = var.deploy_extended_items ? 1 : 0

  workspace_id = var.workspace_id
  display_name = var.eventhouse_name
  description  = "Real-time analytics eventhouse managed by Terraform."

  lifecycle {
    prevent_destroy = true
  }
}

# ---- KQL Database -----------------------------------------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/kql_database
resource "fabric_kql_database" "this" {
  count = var.deploy_extended_items ? 1 : 0

  workspace_id = var.workspace_id
  display_name = var.kql_database_name
  description  = "Writable KQL database managed by Terraform."

  configuration = {
    database_type = "ReadWrite"
    eventhouse_id = fabric_eventhouse.this[0].id
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---- Variable Library -------------------------------------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/variable_library
resource "fabric_variable_library" "this" {
  count = var.deploy_extended_items ? 1 : 0

  workspace_id = var.workspace_id
  display_name = var.variable_library_name
  description  = "Deployment configuration library managed by Terraform."

  lifecycle {
    prevent_destroy = true
  }
}

# ---- ML Experiment ----------------------------------------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/ml_experiment
resource "fabric_ml_experiment" "this" {
  count = var.deploy_extended_items ? 1 : 0

  workspace_id = var.workspace_id
  display_name = var.ml_experiment_name
  description  = "Machine learning experiment managed by Terraform."

  lifecycle {
    prevent_destroy = true
  }
}

# ---- Notebook ---------------------------------------------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/notebook
resource "fabric_notebook" "this" {
  workspace_id              = var.workspace_id
  display_name              = var.notebook_name
  format                    = "py"
  definition_update_enabled = true

  definition = {
    "notebook-content.py" = {
      source          = "${local.notebook_source_dir}/notebook-content.py"
      processing_mode = "None"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---- Data Pipeline (references the notebook id) -----------------------------
# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/data_pipeline
resource "fabric_data_pipeline" "this" {
  count = var.deploy_extended_items ? 1 : 0

  workspace_id              = var.workspace_id
  display_name              = var.pipeline_name
  format                    = "Default"
  definition_update_enabled = true

  definition = {
    "pipeline-content.json" = {
      source          = "${local.pipeline_source_dir}/pipeline-content.json"
      processing_mode = "Parameters"
      parameters = [
        { type = "TextReplace", find = local.source_notebook_logical_id, value = fabric_notebook.this.id },
        { type = "TextReplace", find = local.neutral_workspace_id, value = var.workspace_id },
      ]
    }
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(regexall(local.source_notebook_logical_id, file("${local.pipeline_source_dir}/pipeline-content.json"))) == 1
      error_message = "The canonical Pipeline must reference the source Notebook logical ID exactly once."
    }

    precondition {
      condition     = length(regexall(local.neutral_workspace_id, file("${local.pipeline_source_dir}/pipeline-content.json"))) == 1
      error_message = "The canonical Pipeline must contain exactly one neutral workspace ID."
    }
  }
}

moved {
  from = fabric_environment.this
  to   = fabric_environment.this[0]
}

moved {
  from = fabric_eventhouse.this
  to   = fabric_eventhouse.this[0]
}

moved {
  from = fabric_kql_database.this
  to   = fabric_kql_database.this[0]
}

moved {
  from = fabric_variable_library.this
  to   = fabric_variable_library.this[0]
}

moved {
  from = fabric_ml_experiment.this
  to   = fabric_ml_experiment.this[0]
}

moved {
  from = fabric_data_pipeline.this
  to   = fabric_data_pipeline.this[0]
}
