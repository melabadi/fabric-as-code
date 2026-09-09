# =============================================================================
# 05-deploy-items.ps1 — create the Fabric items inside the workspace:
#   Lakehouse, Warehouse, Environment, Eventhouse, KQL Database,
#   Variable Library, ML Experiment, Notebook, Data Pipeline.
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
$environmentName = if ($cfg.ContainsKey('ENVIRONMENT_NAME') -and $cfg.ENVIRONMENT_NAME) {
    $cfg.ENVIRONMENT_NAME
} else {
    'env_demo_spark'
}
$eventhouseName = if ($cfg.ContainsKey('EVENTHOUSE_NAME') -and $cfg.EVENTHOUSE_NAME) {
    $cfg.EVENTHOUSE_NAME
} else {
    'eh_demo_events'
}
$kqlDatabaseName = if ($cfg.ContainsKey('KQL_DATABASE_NAME') -and $cfg.KQL_DATABASE_NAME) {
    $cfg.KQL_DATABASE_NAME
} else {
    'kqldb_demo_events'
}
$variableLibraryName = if ($cfg.ContainsKey('VARIABLE_LIBRARY_NAME') -and $cfg.VARIABLE_LIBRARY_NAME) {
    $cfg.VARIABLE_LIBRARY_NAME
} else {
    'vl_demo_config'
}
$mlExperimentName = if ($cfg.ContainsKey('ML_EXPERIMENT_NAME') -and $cfg.ML_EXPERIMENT_NAME) {
    $cfg.ML_EXPERIMENT_NAME
} else {
    'mlexp_demo_forecast'
}

# Helper: find an item by display name + type within the workspace.
function Get-ItemId {
    param([string] $Type, [string] $DisplayName)
    $items = Invoke-FabricApi -Method Get -Path "/workspaces/$workspaceId/items" -Token $token
    $match = $items.value | Where-Object { $_.type -ieq $Type -and $_.displayName -ieq $DisplayName }
    if ($match) { return @($match)[0].id }
    return $null
}

function Wait-ItemId {
    param([string] $Type, [string] $DisplayName)
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $itemId = Get-ItemId -Type $Type -DisplayName $DisplayName
        if ($itemId) { return $itemId }
        if ($attempt -lt 29) { Start-Sleep -Seconds 5 }
    }
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
    $lakehouseId = if ($lh -and $lh.id) { $lh.id } else {
        Wait-ItemId -Type 'Lakehouse' -DisplayName $cfg.LAKEHOUSE_NAME
    }
    if (-not $lakehouseId) { throw 'Lakehouse did not become available in time.' }
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
        $warehouseId = Wait-ItemId -Type 'Warehouse' -DisplayName $cfg.WAREHOUSE_NAME
    }
    if (-not $warehouseId) { throw 'Warehouse did not become available in time.' }
    Write-Ok "Warehouse created ($warehouseId)"
}

# ---- Environment -------------------------------------------------------------
Write-Step "Creating Environment '$environmentName'"
$environmentId = Get-ItemId -Type 'Environment' -DisplayName $environmentName
if ($environmentId) {
    Write-Ok "Environment exists ($environmentId)"
} else {
    $environment = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/environments" `
        -Body @{
            displayName = $environmentName
            description = 'Spark environment managed by fabric-as-code.'
        } -Token $token
    $environmentId = if ($environment -and $environment.id) {
        $environment.id
    } else {
        Wait-ItemId -Type 'Environment' -DisplayName $environmentName
    }
    if (-not $environmentId) { throw 'Environment did not become available in time.' }
    Write-Ok "Environment created ($environmentId)"
}

# ---- Eventhouse --------------------------------------------------------------
Write-Step "Creating Eventhouse '$eventhouseName'"
$eventhouseId = Get-ItemId -Type 'Eventhouse' -DisplayName $eventhouseName
if ($eventhouseId) {
    Write-Ok "Eventhouse exists ($eventhouseId)"
} else {
    $eventhouse = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/eventhouses" `
        -Body @{
            displayName = $eventhouseName
            description = 'Real-time analytics eventhouse managed by fabric-as-code.'
        } -Token $token
    $eventhouseId = if ($eventhouse -and $eventhouse.id) {
        $eventhouse.id
    } else {
        Wait-ItemId -Type 'Eventhouse' -DisplayName $eventhouseName
    }
    if (-not $eventhouseId) { throw 'Eventhouse did not become available in time.' }
    Write-Ok "Eventhouse created ($eventhouseId)"
}

# ---- KQL Database ------------------------------------------------------------
Write-Step "Creating KQL Database '$kqlDatabaseName'"
$kqlDatabaseId = Get-ItemId -Type 'KQLDatabase' -DisplayName $kqlDatabaseName
if ($kqlDatabaseId) {
    Write-Ok "KQL Database exists ($kqlDatabaseId)"
} else {
    $kqlDatabase = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/kqlDatabases" `
        -Body @{
            displayName     = $kqlDatabaseName
            description     = 'Writable KQL database managed by fabric-as-code.'
            creationPayload = @{
                databaseType           = 'ReadWrite'
                parentEventhouseItemId = $eventhouseId
            }
        } -Token $token
    $kqlDatabaseId = if ($kqlDatabase -and $kqlDatabase.id) {
        $kqlDatabase.id
    } else {
        Wait-ItemId -Type 'KQLDatabase' -DisplayName $kqlDatabaseName
    }
    if (-not $kqlDatabaseId) { throw 'KQL Database did not become available in time.' }
    Write-Ok "KQL Database created ($kqlDatabaseId)"
}

# ---- Variable Library --------------------------------------------------------
Write-Step "Creating Variable Library '$variableLibraryName'"
$variableLibraryId = Get-ItemId -Type 'VariableLibrary' -DisplayName $variableLibraryName
if ($variableLibraryId) {
    Write-Ok "Variable Library exists ($variableLibraryId)"
} else {
    $variableLibrary = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/variableLibraries" `
        -Body @{
            displayName = $variableLibraryName
            description = 'Deployment configuration library managed by fabric-as-code.'
        } -Token $token
    $variableLibraryId = if ($variableLibrary -and $variableLibrary.id) {
        $variableLibrary.id
    } else {
        Wait-ItemId -Type 'VariableLibrary' -DisplayName $variableLibraryName
    }
    if (-not $variableLibraryId) { throw 'Variable Library did not become available in time.' }
    Write-Ok "Variable Library created ($variableLibraryId)"
}

# ---- ML Experiment -----------------------------------------------------------
Write-Step "Creating ML Experiment '$mlExperimentName'"
$mlExperimentId = Get-ItemId -Type 'MLExperiment' -DisplayName $mlExperimentName
if ($mlExperimentId) {
    Write-Ok "ML Experiment exists ($mlExperimentId)"
} else {
    $mlExperiment = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/mlExperiments" `
        -Body @{
            displayName = $mlExperimentName
            description = 'Machine learning experiment managed by fabric-as-code.'
        } -Token $token
    $mlExperimentId = if ($mlExperiment -and $mlExperiment.id) {
        $mlExperiment.id
    } else {
        Wait-ItemId -Type 'MLExperiment' -DisplayName $mlExperimentName
    }
    if (-not $mlExperimentId) { throw 'ML Experiment did not become available in time.' }
    Write-Ok "ML Experiment created ($mlExperimentId)"
}

# ---- Notebook (from definition file) -----------------------------------------
Write-Step "Creating Notebook '$($cfg.NOTEBOOK_NAME)'"
$notebookId = Get-ItemId -Type 'Notebook' -DisplayName $cfg.NOTEBOOK_NAME
$nbContent = Get-Content `
    (Join-Path $repoRoot 'fabric-git/nb_git_authoring_demo.Notebook/notebook-content.py') -Raw
$nbDefinition = @{
    format = 'py'
    parts  = @(
        @{
            path        = 'notebook-content.py'
            payload     = (ConvertTo-Base64 -Text $nbContent)
            payloadType = 'InlineBase64'
        }
    )
}
if ($notebookId) {
    Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/items/$notebookId/updateDefinition?updateMetadata=false" `
        -Body @{ definition = $nbDefinition } -Token $token | Out-Null
    Write-Ok "Notebook updated ($notebookId)"
} else {
    $nbBody = @{
        displayName = $cfg.NOTEBOOK_NAME
        definition  = $nbDefinition
    }
    $nb = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/notebooks" -Body $nbBody -Token $token
    $notebookId = if ($nb -and $nb.id) { $nb.id } else {
        Wait-ItemId -Type 'Notebook' -DisplayName $cfg.NOTEBOOK_NAME
    }
    if (-not $notebookId) { throw 'Notebook did not become available in time.' }
    Write-Ok "Notebook created ($notebookId)"
}

# ---- Data Pipeline (templated definition) ------------------------------------
Write-Step "Creating Data Pipeline '$($cfg.PIPELINE_NAME)'"
$pipelineId = Get-ItemId -Type 'DataPipeline' -DisplayName $cfg.PIPELINE_NAME
$plDefinitionPath = Join-Path $repoRoot 'fabric-git/pl_git_authoring_demo.DataPipeline/pipeline-content.json'
$plObject = Get-Content $plDefinitionPath -Raw | ConvertFrom-Json -Depth 100
$notebookActivities = @($plObject.properties.activities | Where-Object { $_.type -eq 'TridentNotebook' })
if ($notebookActivities.Count -ne 1) {
    throw "The canonical Pipeline must contain exactly one TridentNotebook activity; found $($notebookActivities.Count)."
}
$notebookActivities[0].typeProperties.notebookId = $notebookId
$notebookActivities[0].typeProperties.workspaceId = $workspaceId
$plContent = $plObject | ConvertTo-Json -Depth 100 -Compress
$plDefinition = @{
    parts = @(
        @{
            path        = 'pipeline-content.json'
            payload     = (ConvertTo-Base64 -Text $plContent)
            payloadType = 'InlineBase64'
        }
    )
}
if ($pipelineId) {
    Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/items/$pipelineId/updateDefinition?updateMetadata=false" `
        -Body @{ definition = $plDefinition } -Token $token | Out-Null
    Write-Ok "Pipeline updated ($pipelineId)"
} else {
    $plBody = @{
        displayName = $cfg.PIPELINE_NAME
        type        = 'DataPipeline'
        definition  = $plDefinition
    }
    $pl = Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/items" -Body $plBody -Token $token
    $pipelineId = if ($pl -and $pl.id) { $pl.id } else {
        Wait-ItemId -Type 'DataPipeline' -DisplayName $cfg.PIPELINE_NAME
    }
    if (-not $pipelineId) { throw 'Data Pipeline did not become available in time.' }
    Write-Ok "Pipeline created ($pipelineId)"
}

# ---- Persist ids --------------------------------------------------------------
$state | Add-Member -NotePropertyName lakehouseId -NotePropertyValue $lakehouseId -Force
$state | Add-Member -NotePropertyName warehouseId -NotePropertyValue $warehouseId -Force
$state | Add-Member -NotePropertyName notebookId  -NotePropertyValue $notebookId  -Force
$state | Add-Member -NotePropertyName pipelineId  -NotePropertyValue $pipelineId  -Force
$state | Add-Member -NotePropertyName environmentId -NotePropertyValue $environmentId -Force
$state | Add-Member -NotePropertyName eventhouseId -NotePropertyValue $eventhouseId -Force
$state | Add-Member -NotePropertyName kqlDatabaseId -NotePropertyValue $kqlDatabaseId -Force
$state | Add-Member -NotePropertyName variableLibraryId -NotePropertyValue $variableLibraryId -Force
$state | Add-Member -NotePropertyName mlExperimentId -NotePropertyValue $mlExperimentId -Force
$state | ConvertTo-Json -Depth 10 | Set-Content $statePath
Write-Ok 'All items deployed. Ids saved to .state.json'
