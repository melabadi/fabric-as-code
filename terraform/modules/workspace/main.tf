# =============================================================================
# modules/workspace — Fabric workspace, bound to the capacity.
# =============================================================================
terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

resource "fabric_workspace" "this" {
  display_name = var.workspace_name
  description  = var.description
  capacity_id  = var.capacity_id
}
