#!/usr/bin/env bash
# =============================================================================
# 00-prerequisites.sh — verify required tooling.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

log_step "Checking prerequisites"

require() {
  if command -v "$1" >/dev/null 2>&1; then log_ok "$1 found"; else
    echo "$1 not found. $2" >&2; exit 1; fi
}

require az   "Install Azure CLI: https://aka.ms/azcli"
require jq   "Install jq: https://jqlang.github.io/jq/"
require curl "curl is required."

if command -v sqlcmd >/dev/null 2>&1; then
  log_ok "sqlcmd found (needed for stored procedures)"
else
  log_warn "sqlcmd not found. Install go-sqlcmd for step 06: https://aka.ms/go-sqlcmd"
fi

if az account show >/dev/null 2>&1; then
  log_ok "Azure CLI is logged in"
else
  log_warn "Not logged in. Run 01-login.sh next."
fi
echo "Prerequisite check complete."
