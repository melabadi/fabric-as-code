#!/usr/bin/env bash
# =============================================================================
# 02-provision-capacity.sh — create RG + Fabric capacity via Bicep.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_env

BICEP="${REPO_ROOT}/infra/capacity.bicep"

log_step "Ensuring resource group '$RESOURCE_GROUP' exists"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
log_ok "Resource group ready."

# Build JSON array of admins from the comma-separated value.
ADMINS_JSON="$(echo "$CAPACITY_ADMINS" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')"

log_step "Deploying Fabric capacity '$CAPACITY_NAME' (SKU $CAPACITY_SKU)"
RESOURCE_ID="$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP" \
  --parameters \
      capacityName="$CAPACITY_NAME" \
      location="$LOCATION" \
      skuName="$CAPACITY_SKU" \
      adminMembers="$ADMINS_JSON" \
  --query properties.outputs.capacityResourceId.value -o tsv)"

log_ok "Capacity provisioned: $RESOURCE_ID"
echo "    Note: the capacity may take a few minutes to appear in the Fabric /capacities list."
