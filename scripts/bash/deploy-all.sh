#!/usr/bin/env bash
# =============================================================================
# deploy-all.sh — run the full end-to-end Fabric-as-Code deployment.
# Usage:
#   ./scripts/bash/deploy-all.sh
#   SKIP_LOGIN=1 SKIP_STOREDPROCS=1 ./scripts/bash/deploy-all.sh
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================ Fabric-as-Code: full deployment ================"

bash "$HERE/00-prerequisites.sh"
[[ "${SKIP_LOGIN:-0}" == "1" ]]       || bash "$HERE/01-login.sh"
bash "$HERE/02-provision-capacity.sh"
bash "$HERE/03-create-workspace.sh"
bash "$HERE/04-assign-capacity.sh"
bash "$HERE/05-deploy-items.sh"
[[ "${SKIP_STOREDPROCS:-0}" == "1" ]] || bash "$HERE/06-deploy-stored-procedures.sh"

echo "================ Deployment complete ============================"
echo "Open https://app.fabric.microsoft.com to explore the workspace."
