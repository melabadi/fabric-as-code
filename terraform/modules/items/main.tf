# =============================================================================
# modules/items — Lakehouse, Warehouse, Notebook, Data Pipeline.
#
# Notebook and Pipeline reuse the SAME definition files as the scripts
# (../fabric-items/...). The Fabric provider reads the source at plan time and
# performs TextReplace substitution of the __TOKEN__ placeholders at apply time
# (processing_mode = "parameters") — so there is a single source of truth and no
# pre-rendering step is required.
# =============================================================================
terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
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

# ---- Notebook (bound to the Lakehouse via __TOKEN__ substitution) -----------
resource "fabric_notebook" "this" {
  workspace_id              = var.workspace_id
  display_name              = var.notebook_name
  format                    = "ipynb"
  definition_update_enabled = true

  definition = {
    "notebook-content.ipynb" = {
      source          = "${var.fabric_items_dir}/notebooks/notebook-content.ipynb"
      processing_mode = "Parameters"
      parameters = [
        { type = "TextReplace", find = "__LAKEHOUSE_ID__", value = fabric_lakehouse.this.id },
        { type = "TextReplace", find = "__LAKEHOUSE_NAME__", value = var.lakehouse_name },
        { type = "TextReplace", find = "__WORKSPACE_ID__", value = var.workspace_id },
      ]
    }
  }
}

# ---- Data Pipeline (references the notebook id) -----------------------------
resource "fabric_data_pipeline" "this" {
  workspace_id              = var.workspace_id
  display_name              = var.pipeline_name
  format                    = "Default"
  definition_update_enabled = true

  definition = {
    "pipeline-content.json" = {
      source          = "${var.fabric_items_dir}/pipelines/pipeline-content.json"
      processing_mode = "Parameters"
      parameters = [
        { type = "TextReplace", find = "__NOTEBOOK_ID__", value = fabric_notebook.this.id },
        { type = "TextReplace", find = "__WORKSPACE_ID__", value = var.workspace_id },
      ]
    }
  }
}
