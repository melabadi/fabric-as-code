#!/usr/bin/env bash
# =============================================================================
# 99-teardown.sh — delete the workspace and the Azure resource group. DESTRUCTIVE.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

echo "This will DELETE the Fabric workspace and the Azure resource group:"
echo "  Workspace      : $WORKSPACE_NAME"
echo "  Resource group : $RESOURCE_GROUP (includes capacity $CAPACITY_NAME)"
read -r -p "Type the resource group name to confirm: " CONFIRM
if [[ "$CONFIRM" != "$RESOURCE_GROUP" ]]; then
  echo "Confirmation did not match. Aborting."; exit 0
fi

WS_ID="$(get_workspace_id_by_name "$WORKSPACE_NAME")"
if [[ -n "$WS_ID" ]]; then
  log_step "Deleting workspace $WS_ID"
  fabric_api DELETE "/workspaces/${WS_ID}" >/dev/null
  log_ok "Workspace deleted."
else
  echo "    Workspace not found — skipping."
fi

log_step "Deleting resource group $RESOURCE_GROUP"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
log_ok "Resource group deletion started (async)."

rm -f "$STATE_FILE"
echo "Teardown complete."
