# =============================================================================
# modules/sql — deploy schema/tables/stored procedures to the Warehouse.
#
# Terraform has no native T-SQL execution model, so this uses terraform_data
# provisioner that runs deploy-procs.ps1 (.NET SqlClient + Entra token, reusing
# your az login). Re-runs whenever the SQL files, deployment script, or
# Warehouse change.
# Deployment guide: ../../../docs/deployment/05-content-files.md
# Learn more: https://developer.hashicorp.com/terraform/language/resources/terraform-data
# =============================================================================
resource "terraform_data" "stored_procs" {
  triggers_replace = {
    warehouse_id = var.warehouse_id
    script_hash  = filesha1("${path.module}/deploy-procs.ps1")
    files_hash = sha1(join(",", [
      for f in sort(tolist(fileset(var.sql_dir, "*.sql"))) :
      filesha1("${var.sql_dir}/${f}")
    ]))
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = "& '${path.module}/deploy-procs.ps1' -Server '${var.server}' -Database '${var.warehouse_name}' -SqlDir '${var.sql_dir}'"
  }
}
