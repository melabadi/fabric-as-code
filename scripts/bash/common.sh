#!/usr/bin/env bash
# =============================================================================
# common.sh — shared helpers for the Fabric-as-Code bash scripts.
# Source this from each script:  source "$(dirname "$0")/common.sh"
# Requires: bash, az, jq, curl. (sqlcmd only for stored procedures.)
# =============================================================================
set -euo pipefail

FABRIC_API_BASE="https://api.fabric.microsoft.com/v1"
FABRIC_RESOURCE="https://api.fabric.microsoft.com"

# Repo root = two levels up from scripts/bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_FILE="${REPO_ROOT}/.state.json"

log_step() { printf '\033[36m==> %s\033[0m\n' "$1"; }
log_ok()   { printf '\033[32m    [ok] %s\033[0m\n' "$1"; }
log_warn() { printf '\033[33m    [warn] %s\033[0m\n' "$1"; }

# ---- Load .env -------------------------------------------------------------
load_env() {
  local env_path="${1:-${REPO_ROOT}/.env}"
  if [[ ! -f "$env_path" ]]; then
    echo "Config file '$env_path' not found. Copy .env.example to .env and fill it in." >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$env_path"
  set +a
  log_ok "Loaded configuration from $env_path"
}

# ---- Tokens ----------------------------------------------------------------
get_token() { az account get-access-token --resource "$1" --query accessToken -o tsv; }
get_fabric_token() { get_token "$FABRIC_RESOURCE"; }

# ---- Fabric REST call with LRO handling ------------------------------------
# Usage: fabric_api <METHOD> <PATH> [JSON_BODY]
# Echoes the JSON response body (or LRO result) to stdout.
fabric_api() {
  local method="$1" path="$2" body="${3:-}"
  local token; token="$(get_fabric_token)"
  local tmp_headers; tmp_headers="$(mktemp)"
  local args=(-sS -X "$method" "${FABRIC_API_BASE}${path}"
              -H "Authorization: Bearer ${token}"
              -H "Content-Type: application/json"
              -D "$tmp_headers" -o /tmp/fabric_body.$$ -w '%{http_code}')
  [[ -n "$body" ]] && args+=(-d "$body")

  local code; code="$(curl "${args[@]}")"
  local resp; resp="$(cat /tmp/fabric_body.$$)"; rm -f /tmp/fabric_body.$$

  if [[ "$code" == "202" ]]; then
    local op_url; op_url="$(grep -i '^Operation-Location:' "$tmp_headers" | tr -d '\r' | awk '{print $2}')"
    rm -f "$tmp_headers"
    if [[ -z "$op_url" ]]; then
      # Some 202 responses (e.g. assignToCapacity) complete without a pollable
      # operation URL. Treat as accepted/success.
      echo ""
      return
    fi
    wait_operation "$op_url" "$token"
    return
  fi
  rm -f "$tmp_headers"

  if [[ "$code" -ge 400 ]]; then
    echo "Fabric API $method $path failed ($code): $resp" >&2
    exit 1
  fi
  echo "$resp"
}

wait_operation() {
  local op_url="$1" token="$2" deadline=$(( $(date +%s) + 600 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    local op; op="$(curl -sS -H "Authorization: Bearer ${token}" "$op_url")"
    local status; status="$(echo "$op" | jq -r '.status')"
    case "$status" in
      Succeeded) curl -sS -H "Authorization: Bearer ${token}" "${op_url}/result" 2>/dev/null || echo "$op"; return ;;
      Failed)    echo "Operation failed: $op" >&2; exit 1 ;;
      *)         sleep 5 ;;
    esac
  done
  echo "Operation timed out." >&2; exit 1
}

# ---- Lookups ---------------------------------------------------------------
get_capacity_id() {
  local name="$1"
  fabric_api GET "/capacities" | jq -r --arg n "$name" '.value[] | select(.displayName|ascii_downcase == ($n|ascii_downcase)) | .id'
}
get_workspace_id_by_name() {
  local name="$1"
  fabric_api GET "/workspaces" | jq -r --arg n "$name" '.value[] | select(.displayName|ascii_downcase == ($n|ascii_downcase)) | .id'
}
get_item_id() {
  local ws="$1" type="$2" name="$3"
  fabric_api GET "/workspaces/${ws}/items" | jq -r --arg t "$type" --arg n "$name" \
    '.value[] | select((.type|ascii_downcase==($t|ascii_downcase)) and (.displayName|ascii_downcase==($n|ascii_downcase))) | .id'
}

# ---- State helpers (JSON via jq) -------------------------------------------
state_get() { [[ -f "$STATE_FILE" ]] && jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE" || echo ""; }
state_set() {
  local key="$1" val="$2"
  [[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"
  local tmp; tmp="$(mktemp)"
  jq --arg k "$key" --arg v "$val" '.[$k]=$v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

b64() { base64 | tr -d '\n'; }
