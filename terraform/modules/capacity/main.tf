# =============================================================================
# modules/capacity — Fabric capacity (Azure) + lookup of its Fabric GUID.
# =============================================================================
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    fabric  = { source = "microsoft/fabric" }
  }
}

resource "azurerm_fabric_capacity" "this" {
  name                = var.capacity_name
  resource_group_name = var.resource_group_name
  location            = var.location

  administration_members = var.admin_members

  sku {
    name = var.sku_name
    tier = "Fabric"
  }

  tags = var.tags
}

# The assignToCapacity API and the Fabric provider need the capacity OBJECT GUID,
# which differs from the ARM resource name. Look it up by display name.
data "fabric_capacity" "this" {
  display_name = azurerm_fabric_capacity.this.name

  lifecycle {
    postcondition {
      condition     = self.id != ""
      error_message = "Fabric capacity '${var.capacity_name}' was not found via the Fabric API. Ensure the running identity is a capacity admin."
    }
  }
}
