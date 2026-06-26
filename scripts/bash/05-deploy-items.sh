#!/usr/bin/env bash
# =============================================================================
# 05-deploy-items.sh — create Lakehouse, Warehouse, Notebook, Data Pipeline.
# Idempotent: existing items with the same display name are reused.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

WS_ID="$(state_get workspaceId)"
[[ -n "$WS_ID" ]] || { echo "workspaceId missing. Run earlier steps first." >&2; exit 1; }

# ---- Lakehouse --------------------------------------------------------------
log_step "Creating Lakehouse '$LAKEHOUSE_NAME'"
LH_ID="$(get_item_id "$WS_ID" Lakehouse "$LAKEHOUSE_NAME")"
if [[ -z "$LH_ID" ]]; then
  BODY="$(jq -n --arg n "$LAKEHOUSE_NAME" '{displayName:$n}')"
  LH_ID="$(fabric_api POST "/workspaces/${WS_ID}/lakehouses" "$BODY" | jq -r '.id')"
fi
log_ok "Lakehouse: $LH_ID"

# ---- Warehouse (LRO) --------------------------------------------------------
log_step "Creating Warehouse '$WAREHOUSE_NAME'"
WH_ID="$(get_item_id "$WS_ID" Warehouse "$WAREHOUSE_NAME")"
if [[ -z "$WH_ID" ]]; then
  BODY="$(jq -n --arg n "$WAREHOUSE_NAME" '{displayName:$n}')"
  fabric_api POST "/workspaces/${WS_ID}/warehouses" "$BODY" >/dev/null
  WH_ID="$(get_item_id "$WS_ID" Warehouse "$WAREHOUSE_NAME")"
fi
log_ok "Warehouse: $WH_ID"

# ---- Notebook (from definition) ---------------------------------------------
log_step "Creating Notebook '$NOTEBOOK_NAME'"
NB_ID="$(get_item_id "$WS_ID" Notebook "$NOTEBOOK_NAME")"
if [[ -z "$NB_ID" ]]; then
  NB_CONTENT="$(sed -e "s/__LAKEHOUSE_ID__/${LH_ID}/g" -e "s/__LAKEHOUSE_NAME__/${LAKEHOUSE_NAME}/g" -e "s/__WORKSPACE_ID__/${WS_ID}/g" \
                 "${REPO_ROOT}/fabric-items/notebooks/notebook-content.ipynb")"
  NB_PAYLOAD="$(printf '%s' "$NB_CONTENT" | b64)"
  BODY="$(jq -n --arg n "$NOTEBOOK_NAME" --arg p "$NB_PAYLOAD" \
    '{displayName:$n, definition:{format:"ipynb", parts:[{path:"notebook-content.ipynb", payload:$p, payloadType:"InlineBase64"}]}}')"
  fabric_api POST "/workspaces/${WS_ID}/notebooks" "$BODY" >/dev/null
  NB_ID="$(get_item_id "$WS_ID" Notebook "$NOTEBOOK_NAME")"
fi
log_ok "Notebook: $NB_ID"

# ---- Data Pipeline (templated) ----------------------------------------------
log_step "Creating Data Pipeline '$PIPELINE_NAME'"
PL_ID="$(get_item_id "$WS_ID" DataPipeline "$PIPELINE_NAME")"
if [[ -z "$PL_ID" ]]; then
  PL_CONTENT="$(sed -e "s/__NOTEBOOK_ID__/${NB_ID}/g" -e "s/__WORKSPACE_ID__/${WS_ID}/g" \
                 "${REPO_ROOT}/fabric-items/pipelines/pipeline-content.json")"
  PL_PAYLOAD="$(printf '%s' "$PL_CONTENT" | b64)"
  BODY="$(jq -n --arg n "$PIPELINE_NAME" --arg p "$PL_PAYLOAD" \
    '{displayName:$n, type:"DataPipeline", definition:{parts:[{path:"pipeline-content.json", payload:$p, payloadType:"InlineBase64"}]}}')"
  fabric_api POST "/workspaces/${WS_ID}/items" "$BODY" >/dev/null
  PL_ID="$(get_item_id "$WS_ID" DataPipeline "$PIPELINE_NAME")"
fi
log_ok "Pipeline: $PL_ID"

state_set lakehouseId "$LH_ID"
state_set warehouseId "$WH_ID"
state_set notebookId  "$NB_ID"
state_set pipelineId  "$PL_ID"
log_ok "All items deployed. Ids saved to .state.json"
