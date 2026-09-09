#!/usr/bin/env bash
# =============================================================================
# 05-deploy-items.sh — create or update all managed Fabric workspace items.
# Idempotent: existing items with the same display name are reused.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

WS_ID="$(state_get workspaceId)"
[[ -n "$WS_ID" ]] || { echo "workspaceId missing. Run earlier steps first." >&2; exit 1; }
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-env_demo_spark}"
EVENTHOUSE_NAME="${EVENTHOUSE_NAME:-eh_demo_events}"
KQL_DATABASE_NAME="${KQL_DATABASE_NAME:-kqldb_demo_events}"
VARIABLE_LIBRARY_NAME="${VARIABLE_LIBRARY_NAME:-vl_demo_config}"
ML_EXPERIMENT_NAME="${ML_EXPERIMENT_NAME:-mlexp_demo_forecast}"

wait_for_item_id() {
  local workspace_id="$1" type="$2" display_name="$3" item_id attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    item_id="$(get_item_id "$workspace_id" "$type" "$display_name")"
    if [[ -n "$item_id" ]]; then
      printf '%s' "$item_id"
      return 0
    fi
    ((attempt < 29)) && sleep 5
  done
  return 1
}

# ---- Lakehouse --------------------------------------------------------------
log_step "Creating Lakehouse '$LAKEHOUSE_NAME'"
LH_ID="$(get_item_id "$WS_ID" Lakehouse "$LAKEHOUSE_NAME")"
if [[ -z "$LH_ID" ]]; then
  BODY="$(jq -n --arg n "$LAKEHOUSE_NAME" '{displayName:$n}')"
  fabric_api POST "/workspaces/${WS_ID}/lakehouses" "$BODY" >/dev/null
  LH_ID="$(wait_for_item_id "$WS_ID" Lakehouse "$LAKEHOUSE_NAME" || true)"
fi
[[ -n "$LH_ID" ]] || { echo "Lakehouse did not become available in time." >&2; exit 1; }
log_ok "Lakehouse: $LH_ID"

# ---- Warehouse (LRO) --------------------------------------------------------
log_step "Creating Warehouse '$WAREHOUSE_NAME'"
WH_ID="$(get_item_id "$WS_ID" Warehouse "$WAREHOUSE_NAME")"
if [[ -z "$WH_ID" ]]; then
  BODY="$(jq -n --arg n "$WAREHOUSE_NAME" '{displayName:$n}')"
  fabric_api POST "/workspaces/${WS_ID}/warehouses" "$BODY" >/dev/null
  WH_ID="$(wait_for_item_id "$WS_ID" Warehouse "$WAREHOUSE_NAME" || true)"
fi
[[ -n "$WH_ID" ]] || { echo "Warehouse did not become available in time." >&2; exit 1; }
log_ok "Warehouse: $WH_ID"

# ---- Environment ------------------------------------------------------------
log_step "Creating Environment '$ENVIRONMENT_NAME'"
ENV_ID="$(get_item_id "$WS_ID" Environment "$ENVIRONMENT_NAME")"
if [[ -z "$ENV_ID" ]]; then
  BODY="$(jq -n --arg n "$ENVIRONMENT_NAME" \
    '{displayName:$n, description:"Spark environment managed by fabric-as-code."}')"
  fabric_api POST "/workspaces/${WS_ID}/environments" "$BODY" >/dev/null
  ENV_ID="$(wait_for_item_id "$WS_ID" Environment "$ENVIRONMENT_NAME" || true)"
fi
[[ -n "$ENV_ID" ]] || { echo "Environment did not become available in time." >&2; exit 1; }
log_ok "Environment: $ENV_ID"

# ---- Eventhouse -------------------------------------------------------------
log_step "Creating Eventhouse '$EVENTHOUSE_NAME'"
EH_ID="$(get_item_id "$WS_ID" Eventhouse "$EVENTHOUSE_NAME")"
if [[ -z "$EH_ID" ]]; then
  BODY="$(jq -n --arg n "$EVENTHOUSE_NAME" \
    '{displayName:$n, description:"Real-time analytics eventhouse managed by fabric-as-code."}')"
  fabric_api POST "/workspaces/${WS_ID}/eventhouses" "$BODY" >/dev/null
  EH_ID="$(wait_for_item_id "$WS_ID" Eventhouse "$EVENTHOUSE_NAME" || true)"
fi
[[ -n "$EH_ID" ]] || { echo "Eventhouse did not become available in time." >&2; exit 1; }
log_ok "Eventhouse: $EH_ID"

# ---- KQL Database -----------------------------------------------------------
log_step "Creating KQL Database '$KQL_DATABASE_NAME'"
KQL_DB_ID="$(get_item_id "$WS_ID" KQLDatabase "$KQL_DATABASE_NAME")"
if [[ -z "$KQL_DB_ID" ]]; then
  BODY="$(jq -n --arg n "$KQL_DATABASE_NAME" --arg eh "$EH_ID" \
    '{displayName:$n, description:"Writable KQL database managed by fabric-as-code.", creationPayload:{databaseType:"ReadWrite", parentEventhouseItemId:$eh}}')"
  fabric_api POST "/workspaces/${WS_ID}/kqlDatabases" "$BODY" >/dev/null
  KQL_DB_ID="$(wait_for_item_id "$WS_ID" KQLDatabase "$KQL_DATABASE_NAME" || true)"
fi
[[ -n "$KQL_DB_ID" ]] || { echo "KQL Database did not become available in time." >&2; exit 1; }
log_ok "KQL Database: $KQL_DB_ID"

# ---- Variable Library -------------------------------------------------------
log_step "Creating Variable Library '$VARIABLE_LIBRARY_NAME'"
VL_ID="$(get_item_id "$WS_ID" VariableLibrary "$VARIABLE_LIBRARY_NAME")"
if [[ -z "$VL_ID" ]]; then
  BODY="$(jq -n --arg n "$VARIABLE_LIBRARY_NAME" \
    '{displayName:$n, description:"Deployment configuration library managed by fabric-as-code."}')"
  fabric_api POST "/workspaces/${WS_ID}/variableLibraries" "$BODY" >/dev/null
  VL_ID="$(wait_for_item_id "$WS_ID" VariableLibrary "$VARIABLE_LIBRARY_NAME" || true)"
fi
[[ -n "$VL_ID" ]] || { echo "Variable Library did not become available in time." >&2; exit 1; }
log_ok "Variable Library: $VL_ID"

# ---- ML Experiment ----------------------------------------------------------
log_step "Creating ML Experiment '$ML_EXPERIMENT_NAME'"
ML_EXP_ID="$(get_item_id "$WS_ID" MLExperiment "$ML_EXPERIMENT_NAME")"
if [[ -z "$ML_EXP_ID" ]]; then
  BODY="$(jq -n --arg n "$ML_EXPERIMENT_NAME" \
    '{displayName:$n, description:"Machine learning experiment managed by fabric-as-code."}')"
  fabric_api POST "/workspaces/${WS_ID}/mlExperiments" "$BODY" >/dev/null
  ML_EXP_ID="$(wait_for_item_id "$WS_ID" MLExperiment "$ML_EXPERIMENT_NAME" || true)"
fi
[[ -n "$ML_EXP_ID" ]] || { echo "ML Experiment did not become available in time." >&2; exit 1; }
log_ok "ML Experiment: $ML_EXP_ID"

# ---- Notebook (from definition) ---------------------------------------------
log_step "Creating Notebook '$NOTEBOOK_NAME'"
NB_ID="$(get_item_id "$WS_ID" Notebook "$NOTEBOOK_NAME")"
NB_PAYLOAD="$(b64 < "${REPO_ROOT}/fabric-git/nb_git_authoring_demo.Notebook/notebook-content.py")"
NB_DEFINITION="$(jq -n --arg p "$NB_PAYLOAD" \
  '{definition:{format:"py", parts:[{path:"notebook-content.py", payload:$p, payloadType:"InlineBase64"}]}}')"
if [[ -z "$NB_ID" ]]; then
  BODY="$(jq -n --arg n "$NOTEBOOK_NAME" --arg p "$NB_PAYLOAD" \
    '{displayName:$n, definition:{format:"py", parts:[{path:"notebook-content.py", payload:$p, payloadType:"InlineBase64"}]}}')"
  fabric_api POST "/workspaces/${WS_ID}/notebooks" "$BODY" >/dev/null
  NB_ID="$(wait_for_item_id "$WS_ID" Notebook "$NOTEBOOK_NAME" || true)"
else
  fabric_api POST "/workspaces/${WS_ID}/items/${NB_ID}/updateDefinition?updateMetadata=false" "$NB_DEFINITION" >/dev/null
fi
[[ -n "$NB_ID" ]] || { echo "Notebook did not become available in time." >&2; exit 1; }
log_ok "Notebook: $NB_ID"

# ---- Data Pipeline (templated) ----------------------------------------------
log_step "Creating Data Pipeline '$PIPELINE_NAME'"
PL_ID="$(get_item_id "$WS_ID" DataPipeline "$PIPELINE_NAME")"
PL_SOURCE="${REPO_ROOT}/fabric-git/pl_git_authoring_demo.DataPipeline/pipeline-content.json"
NOTEBOOK_ACTIVITY_COUNT="$(jq '[.properties.activities[] | select(.type == "TridentNotebook")] | length' "$PL_SOURCE")"
[[ "$NOTEBOOK_ACTIVITY_COUNT" -eq 1 ]] || {
  echo "The canonical Pipeline must contain exactly one TridentNotebook activity; found $NOTEBOOK_ACTIVITY_COUNT." >&2
  exit 1
}
PL_CONTENT="$(jq --arg notebookId "$NB_ID" --arg workspaceId "$WS_ID" \
  '(.properties.activities[] | select(.type == "TridentNotebook") | .typeProperties.notebookId) = $notebookId |
   (.properties.activities[] | select(.type == "TridentNotebook") | .typeProperties.workspaceId) = $workspaceId' \
  "$PL_SOURCE")"
PL_PAYLOAD="$(printf '%s' "$PL_CONTENT" | b64)"
PL_DEFINITION="$(jq -n --arg p "$PL_PAYLOAD" \
  '{definition:{parts:[{path:"pipeline-content.json", payload:$p, payloadType:"InlineBase64"}]}}')"
if [[ -z "$PL_ID" ]]; then
  BODY="$(jq -n --arg n "$PIPELINE_NAME" --arg p "$PL_PAYLOAD" \
    '{displayName:$n, type:"DataPipeline", definition:{parts:[{path:"pipeline-content.json", payload:$p, payloadType:"InlineBase64"}]}}')"
  fabric_api POST "/workspaces/${WS_ID}/items" "$BODY" >/dev/null
  PL_ID="$(wait_for_item_id "$WS_ID" DataPipeline "$PIPELINE_NAME" || true)"
else
  fabric_api POST "/workspaces/${WS_ID}/items/${PL_ID}/updateDefinition?updateMetadata=false" "$PL_DEFINITION" >/dev/null
fi
[[ -n "$PL_ID" ]] || { echo "Data Pipeline did not become available in time." >&2; exit 1; }
log_ok "Pipeline: $PL_ID"

state_set lakehouseId "$LH_ID"
state_set warehouseId "$WH_ID"
state_set notebookId  "$NB_ID"
state_set pipelineId  "$PL_ID"
state_set environmentId "$ENV_ID"
state_set eventhouseId "$EH_ID"
state_set kqlDatabaseId "$KQL_DB_ID"
state_set variableLibraryId "$VL_ID"
state_set mlExperimentId "$ML_EXP_ID"
log_ok "All items deployed. Ids saved to .state.json"
