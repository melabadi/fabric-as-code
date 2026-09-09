#!/usr/bin/env bash
# =============================================================================
# 03-create-workspace.sh — create (or reuse) the Fabric workspace.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

log_step "Creating workspace '$WORKSPACE_NAME'"
WS_ID="$(get_workspace_id_by_name "$WORKSPACE_NAME")"

if [[ -n "$WS_ID" ]]; then
  log_ok "Workspace already exists ($WS_ID) — reusing."
else
  BODY="$(jq -n --arg n "$WORKSPACE_NAME" --arg d "$WORKSPACE_DESCRIPTION" \
            '{displayName:$n, description:$d}')"
  WS_ID="$(fabric_api POST "/workspaces" "$BODY" | jq -r '.id')"
  log_ok "Workspace created: $WS_ID"
fi

state_set workspaceId "$WS_ID"
log_ok "Saved workspaceId to .state.json"
