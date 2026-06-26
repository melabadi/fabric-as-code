# =============================================================================
# modules/sql — deploy schema/tables/stored procedures to the Warehouse.
#
# Terraform has no native T-SQL execution model, so this uses a null_resource
# provisioner that runs deploy-procs.ps1 (.NET SqlClient + Entra token, reusing
# your az login). Re-runs whenever the SQL files or the warehouse change.
# =============================================================================
terraform {
  required_providers {
    null = { source = "hashicorp/null" }
  }
}

resource "null_resource" "stored_procs" {
  triggers = {
    warehouse_id = var.warehouse_id
    files_hash = sha1(join(",", [
      for f in sort(tolist(fileset(var.sql_dir, "*.sql"))) :
      filesha1("${var.sql_dir}/${f}")
    ]))
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = "& '${path.module}/deploy-procs.ps1' -WorkspaceId '${var.workspace_id}' -WarehouseId '${var.warehouse_id}' -Database '${var.warehouse_name}' -SqlDir '${var.sql_dir}'"
  }
}
