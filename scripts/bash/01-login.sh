#!/usr/bin/env bash
# =============================================================================
# 01-login.sh — authenticate to Azure / Entra ID (SP if configured, else interactive).
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

log_step "Authenticating to Azure"
if [[ -n "${SP_CLIENT_ID:-}" && -n "${SP_CLIENT_SECRET:-}" ]]; then
  echo "    Using service principal login (non-interactive)."
  az login --service-principal \
    --username "$SP_CLIENT_ID" \
    --password "$SP_CLIENT_SECRET" \
    --tenant   "$TENANT_ID" --output none
else
  echo "    Using interactive login."
  az login --tenant "$TENANT_ID" --output none
fi

az account set --subscription "$SUBSCRIPTION_ID" --output none
log_ok "Active subscription set to $SUBSCRIPTION_ID"

get_fabric_token >/dev/null
log_ok "Successfully acquired a Microsoft Fabric API token."
