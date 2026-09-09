#!/usr/bin/env bash
# =============================================================================
# 04-assign-capacity.sh — bind the workspace to the Fabric capacity.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

WS_ID="$(state_get workspaceId)"
[[ -n "$WS_ID" ]] || { echo "workspaceId missing. Run 03-create-workspace.sh first." >&2; exit 1; }

log_step "Resolving capacity id for '$CAPACITY_NAME'"
CAP_ID="$(get_capacity_id "$CAPACITY_NAME")"
[[ -n "$CAP_ID" ]] || { echo "Capacity '$CAPACITY_NAME' not visible. Ensure your identity is a capacity admin." >&2; exit 1; }
log_ok "Capacity id: $CAP_ID"

log_step "Assigning workspace $WS_ID to capacity"
BODY="$(jq -n --arg c "$CAP_ID" '{capacityId:$c}')"
fabric_api POST "/workspaces/${WS_ID}/assignToCapacity" "$BODY" >/dev/null
log_ok "Workspace assigned to capacity."
state_set capacityId "$CAP_ID"
