#!/usr/bin/env bash
# =============================================================================
# 06-deploy-stored-procedures.sh — deploy schema/tables/procs to the Warehouse.
# Uses go-sqlcmd with ActiveDirectoryAzCli (reuses the az login session).
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

WS_ID="$(state_get workspaceId)"
WH_ID="$(state_get warehouseId)"
[[ -n "$WH_ID" ]] || { echo "warehouseId missing. Run 05-deploy-items.sh first." >&2; exit 1; }

command -v sqlcmd >/dev/null 2>&1 || { echo "sqlcmd not found. Install go-sqlcmd: https://aka.ms/go-sqlcmd" >&2; exit 1; }

log_step "Resolving Warehouse SQL connection string"
SERVER="$(fabric_api GET "/workspaces/${WS_ID}/warehouses/${WH_ID}" | jq -r '.properties.connectionString')"
DATABASE="$WAREHOUSE_NAME"
[[ -n "$SERVER" && "$SERVER" != "null" ]] || { echo "Could not read Warehouse connectionString (still provisioning?)." >&2; exit 1; }
log_ok "SQL endpoint: $SERVER / DB: $DATABASE"

for f in 01-create-schema.sql 02-create-tables.sql 03-stored-procedures.sql; do
  log_step "Executing $f"
  sqlcmd -S "$SERVER" -d "$DATABASE" \
    --authentication-method ActiveDirectoryAzCli \
    -i "${REPO_ROOT}/fabric-items/sql/${f}" -b
  log_ok "$f applied."
done

echo "Schema, tables and stored procedures deployed to the Warehouse."
echo "Tip: EXEC sales.usp_seed_orders; then EXEC sales.usp_refresh_orders_summary;"
