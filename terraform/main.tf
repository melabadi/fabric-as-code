# =============================================================================
# main.tf — wires the modules together (capacity -> workspace -> items -> sql).
# =============================================================================

resource "azurerm_resource_group" "this" {
  name     = var.resource_group
  location = var.location
  tags = {
    managedBy = "fabric-as-code"
    iac       = "terraform"
  }
}

module "capacity" {
  source              = "./modules/capacity"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  capacity_name       = var.capacity_name
  sku_name            = var.capacity_sku
  admin_members       = var.capacity_admins
}

module "workspace" {
  source         = "./modules/workspace"
  workspace_name = var.workspace_name
  description    = var.workspace_description
  capacity_id    = module.capacity.capacity_guid
}

module "items" {
  source           = "./modules/items"
  workspace_id     = module.workspace.workspace_id
  lakehouse_name   = var.lakehouse_name
  warehouse_name   = var.warehouse_name
  notebook_name    = var.notebook_name
  pipeline_name    = var.pipeline_name
  fabric_items_dir = "${path.root}/../fabric-items"
}

module "sql" {
  source         = "./modules/sql"
  count          = var.deploy_stored_procedures ? 1 : 0
  workspace_id   = module.workspace.workspace_id
  warehouse_id   = module.items.warehouse_id
  warehouse_name = var.warehouse_name
  sql_dir        = "${path.root}/../fabric-items/sql"
}
