# =============================================================================
# modules/items — Lakehouse, Warehouse, Notebook, Data Pipeline.
#
# Notebook and Pipeline reuse the SAME definition files as the scripts
# (../fabric-items/...). The __TOKENS__ in those files are substituted with the
# real GUIDs here, rendered to a local .rendered/ folder, and uploaded by the
# Fabric provider. This keeps a single source of truth for item definitions.
# =============================================================================
terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
    local  = { source = "hashicorp/local" }
  }
}

# ---- Lakehouse (auto-creates a SQL analytics endpoint) ----------------------
resource "fabric_lakehouse" "this" {
  workspace_id = var.workspace_id
  display_name = var.lakehouse_name
}

# ---- Warehouse --------------------------------------------------------------
resource "fabric_warehouse" "this" {
  workspace_id = var.workspace_id
  display_name = var.warehouse_name
}

# ---- Notebook (bound to the Lakehouse via token substitution) ---------------
locals {
  notebook_rendered = replace(replace(replace(
    file("${var.fabric_items_dir}/notebooks/notebook-content.ipynb"),
    "__LAKEHOUSE_ID__", fabric_lakehouse.this.id),
    "__LAKEHOUSE_NAME__", var.lakehouse_name),
    "__WORKSPACE_ID__", var.workspace_id
  )
}

resource "local_file" "notebook" {
  filename = "${path.module}/.rendered/notebook-content.ipynb"
  content  = local.notebook_rendered
}

resource "fabric_notebook" "this" {
  workspace_id              = var.workspace_id
  display_name              = var.notebook_name
  format                    = "ipynb"
  definition_update_enabled = true

  definition = {
    "notebook-content.ipynb" = {
      source = local_file.notebook.filename
    }
  }
}

# ---- Data Pipeline (references the notebook id) -----------------------------
locals {
  pipeline_rendered = replace(replace(
    file("${var.fabric_items_dir}/pipelines/pipeline-content.json"),
    "__NOTEBOOK_ID__", fabric_notebook.this.id),
    "__WORKSPACE_ID__", var.workspace_id
  )
}

resource "local_file" "pipeline" {
  filename = "${path.module}/.rendered/pipeline-content.json"
  content  = local.pipeline_rendered
}

resource "fabric_data_pipeline" "this" {
  workspace_id              = var.workspace_id
  display_name              = var.pipeline_name
  format                    = "Default"
  definition_update_enabled = true

  definition = {
    "pipeline-content.json" = {
      source = local_file.pipeline.filename
    }
  }
}
