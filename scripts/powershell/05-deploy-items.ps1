# =============================================================================
# 05-deploy-items.ps1 — create the Fabric items inside the workspace:
#   Lakehouse, Warehouse, Notebook (from definition), Data Pipeline (templated).
# Idempotent: existing items with the same display name are reused.
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv
$token = Get-FabricToken

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '../..')
$statePath = Join-Path $repoRoot '.state.json'
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$workspaceId = $state.workspaceId
if (-not $workspaceId) { throw 'workspaceId missing. Run earlier steps first.' }

# Helper: find an item by display name + type within the workspace.
function Get-ItemId {
    param([string] $Type, [string] $DisplayName)
    $items = Invoke-FabricApi -Method Get -Path "/workspaces/$workspaceId/items" -Token $token
    $match = $items.value | Where-Object { $_.type -ieq $Type -and $_.displayName -ieq $DisplayName }
    if ($match) { return @($match)[0].id }
    return $null
}

# ---- Lakehouse ----------------------------------------------------------------
Write-Step "Creating Lakehouse '$($cfg.LAKEHOUSE_NAME)'"
$lakehouseId = Get-ItemId -Type 'Lakehouse' -DisplayName $cfg.LAKEHOUSE_NAME
if ($lakehouseId) {
    Write-Ok "Lakehouse exists ($lakehouseId)"
} else {
    $lh = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/lakehouses" `
        -Body @{ displayName = $cfg.LAKEHOUSE_NAME } -Token $token
    $lakehouseId = $lh.id
    Write-Ok "Lakehouse created ($lakehouseId)"
}

# ---- Warehouse (long-running operation) ---------------------------------------
Write-Step "Creating Warehouse '$($cfg.WAREHOUSE_NAME)'"
$warehouseId = Get-ItemId -Type 'Warehouse' -DisplayName $cfg.WAREHOUSE_NAME
if ($warehouseId) {
    Write-Ok "Warehouse exists ($warehouseId)"
} else {
    $wh = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/warehouses" `
        -Body @{ displayName = $cfg.WAREHOUSE_NAME } -Token $token
    if ($wh -and $wh.id) {
        $warehouseId = $wh.id
    } else {
        # Async create without a pollable url: wait for it to appear in the list.
        for ($i = 0; $i -lt 30 -and -not $warehouseId; $i++) {
            Start-Sleep -Seconds 5
            $warehouseId = Get-ItemId -Type 'Warehouse' -DisplayName $cfg.WAREHOUSE_NAME
        }
    }
    if (-not $warehouseId) { throw 'Warehouse did not become available in time.' }
    Write-Ok "Warehouse created ($warehouseId)"
}

# ---- Notebook (from definition file) -----------------------------------------
Write-Step "Creating Notebook '$($cfg.NOTEBOOK_NAME)'"
$notebookId = Get-ItemId -Type 'Notebook' -DisplayName $cfg.NOTEBOOK_NAME
if ($notebookId) {
    Write-Ok "Notebook exists ($notebookId)"
} else {
    $nbTemplate = Get-Content (Join-Path $repoRoot 'fabric-items/notebooks/notebook-content.ipynb') -Raw
    # Bind the notebook to the Lakehouse so saveAsTable() writes there.
    $nbContent = $nbTemplate `
        -replace '__LAKEHOUSE_ID__', $lakehouseId `
        -replace '__LAKEHOUSE_NAME__', $cfg.LAKEHOUSE_NAME `
        -replace '__WORKSPACE_ID__', $workspaceId
    $nbBody = @{
        displayName = $cfg.NOTEBOOK_NAME
        definition  = @{
            format = 'ipynb'
            parts  = @(
                @{
                    path        = 'notebook-content.ipynb'
                    payload     = (ConvertTo-Base64 -Text $nbContent)
                    payloadType = 'InlineBase64'
                }
            )
        }
    }
    $nb = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/notebooks" -Body $nbBody -Token $token
    $notebookId = if ($nb -and $nb.id) { $nb.id } else { Get-ItemId -Type 'Notebook' -DisplayName $cfg.NOTEBOOK_NAME }
    Write-Ok "Notebook created ($notebookId)"
}

# ---- Data Pipeline (templated definition) ------------------------------------
Write-Step "Creating Data Pipeline '$($cfg.PIPELINE_NAME)'"
$pipelineId = Get-ItemId -Type 'DataPipeline' -DisplayName $cfg.PIPELINE_NAME
if ($pipelineId) {
    Write-Ok "Pipeline exists ($pipelineId)"
} else {
    $plTemplate = Get-Content (Join-Path $repoRoot 'fabric-items/pipelines/pipeline-content.json') -Raw
    $plContent = $plTemplate `
        -replace '__NOTEBOOK_ID__', $notebookId `
        -replace '__WORKSPACE_ID__', $workspaceId
    $plBody = @{
        displayName = $cfg.PIPELINE_NAME
        type        = 'DataPipeline'
        definition  = @{
            parts = @(
                @{
                    path        = 'pipeline-content.json'
                    payload     = (ConvertTo-Base64 -Text $plContent)
                    payloadType = 'InlineBase64'
                }
            )
        }
    }
    $pl = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/items" -Body $plBody -Token $token
    $pipelineId = if ($pl -and $pl.id) { $pl.id } else { Get-ItemId -Type 'DataPipeline' -DisplayName $cfg.PIPELINE_NAME }
    Write-Ok "Pipeline created ($pipelineId)"
}

# ---- Persist ids --------------------------------------------------------------
$state | Add-Member -NotePropertyName lakehouseId -NotePropertyValue $lakehouseId -Force
$state | Add-Member -NotePropertyName warehouseId -NotePropertyValue $warehouseId -Force
$state | Add-Member -NotePropertyName notebookId  -NotePropertyValue $notebookId  -Force
$state | Add-Member -NotePropertyName pipelineId  -NotePropertyValue $pipelineId  -Force
$state | ConvertTo-Json -Depth 10 | Set-Content $statePath
Write-Ok 'All items deployed. Ids saved to .state.json'
