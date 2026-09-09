# =============================================================================
# modules/workspace — Fabric workspace, bound to the capacity.
# Deployment guide: ../../../docs/deployment/02-workspaces.md
# =============================================================================
terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

# Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace
resource "fabric_workspace" "this" {
  display_name                   = var.workspace_name
  description                    = var.description
  capacity_id                    = var.capacity_id
  skip_capacity_state_validation = var.skip_capacity_state_validation
}
