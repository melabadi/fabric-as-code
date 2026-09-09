# =============================================================================
# 03-create-workspace.ps1 — create (or reuse) the Fabric workspace.
# Idempotent: if a workspace with the same display name exists, it is reused.
# Writes the resolved workspace id to .state.json for later steps.
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv
$token = Get-FabricToken

Write-Step "Creating workspace '$($cfg.WORKSPACE_NAME)'"

$existingId = Get-WorkspaceIdByName -WorkspaceName $cfg.WORKSPACE_NAME -Token $token
if ($existingId) {
    Write-Ok "Workspace already exists ($existingId) — reusing."
    $workspaceId = $existingId
} else {
    $body = @{
        displayName = $cfg.WORKSPACE_NAME
        description = $cfg.WORKSPACE_DESCRIPTION
    }
    $ws = Invoke-FabricApi -Method Post -Path '/workspaces' -Body $body -Token $token
    $workspaceId = $ws.id
    Write-Ok "Workspace created: $workspaceId"
}

# Persist state for downstream steps.
$statePath = Join-Path $PSScriptRoot '../../.state.json'
$state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
$state | Add-Member -NotePropertyName workspaceId -NotePropertyValue $workspaceId -Force
$state | ConvertTo-Json -Depth 10 | Set-Content $statePath
Write-Ok "Saved workspaceId to .state.json"
