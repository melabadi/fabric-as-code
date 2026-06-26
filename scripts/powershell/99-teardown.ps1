# =============================================================================
# 99-teardown.ps1 - remove everything provisioned by this repo.
# Deletes the Fabric workspace (and all items), then the Azure resource group
# (which removes the Fabric capacity). DESTRUCTIVE - asks for confirmation.
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv
$token = Get-FabricToken

Write-Host 'This will DELETE the Fabric workspace and the Azure resource group:' -ForegroundColor Red
Write-Host "  Workspace      : $($cfg.WORKSPACE_NAME)"
Write-Host "  Resource group : $($cfg.RESOURCE_GROUP) -- includes capacity $($cfg.CAPACITY_NAME)"
$confirm = Read-Host 'Type the resource group name to confirm'
if ($confirm -ne $cfg.RESOURCE_GROUP) {
    Write-Host 'Confirmation did not match. Aborting.' -ForegroundColor Yellow
    return
}

# ---- Delete the Fabric workspace ----------------------------------------------
$workspaceId = Get-WorkspaceIdByName -WorkspaceName $cfg.WORKSPACE_NAME -Token $token
if ($workspaceId) {
    Write-Step "Deleting workspace $workspaceId"
    Invoke-FabricApi -Method Delete -Path "/workspaces/$workspaceId" -Token $token | Out-Null
    Write-Ok 'Workspace deleted.'
} else {
    Write-Host '    Workspace not found - skipping.' -ForegroundColor DarkGray
}

# ---- Delete the Azure resource group (removes the capacity) --------------------
Write-Step "Deleting resource group $($cfg.RESOURCE_GROUP)"
az group delete --name $cfg.RESOURCE_GROUP --yes --no-wait
Write-Ok 'Resource group deletion started (running async).'

# ---- Clean local state --------------------------------------------------------
$statePath = Join-Path $PSScriptRoot '../../.state.json'
if (Test-Path $statePath) { Remove-Item $statePath }
Write-Host 'Teardown complete.' -ForegroundColor Green
