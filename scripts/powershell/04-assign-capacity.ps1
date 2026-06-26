# =============================================================================
# 04-assign-capacity.ps1 — bind the workspace to the Fabric capacity.
# A workspace must be on a capacity before Fabric (non-Power BI) items work.
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv
$token = Get-FabricToken

$statePath = Join-Path $PSScriptRoot '../../.state.json'
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$workspaceId = $state.workspaceId
if (-not $workspaceId) { throw 'workspaceId missing from .state.json. Run 03-create-workspace.ps1 first.' }

Write-Step "Resolving capacity id for '$($cfg.CAPACITY_NAME)'"
$capacityId = Get-FabricCapacityId -CapacityName $cfg.CAPACITY_NAME -Token $token
Write-Ok "Capacity id: $capacityId"

Write-Step "Assigning workspace $workspaceId to capacity"
$body = @{ capacityId = $capacityId }
Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/assignToCapacity" -Body $body -Token $token | Out-Null
Write-Ok 'Workspace assigned to capacity.'

$state | Add-Member -NotePropertyName capacityId -NotePropertyValue $capacityId -Force
$state | ConvertTo-Json -Depth 10 | Set-Content $statePath
