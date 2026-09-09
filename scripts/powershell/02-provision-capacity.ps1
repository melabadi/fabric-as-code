# =============================================================================
# 02-provision-capacity.ps1 — create the resource group and Fabric capacity
# via Azure CLI + the Bicep template in /infra.
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv

$bicepPath = Join-Path $PSScriptRoot '../../infra/capacity.bicep'

Write-Step "Ensuring resource group '$($cfg.RESOURCE_GROUP)' exists"
az group create `
    --name $cfg.RESOURCE_GROUP `
    --location $cfg.LOCATION `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create or update resource group '$($cfg.RESOURCE_GROUP)'." }
Write-Ok 'Resource group ready.'

# Build the admin members array from the comma-separated .env value.
$admins = @(($cfg.CAPACITY_ADMINS -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Write an ARM parameters file to avoid cross-shell quoting issues with arrays.
$paramObject = @{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = @{
        capacityName = @{ value = $cfg.CAPACITY_NAME }
        location     = @{ value = $cfg.LOCATION }
        skuName      = @{ value = $cfg.CAPACITY_SKU }
        adminMembers = @{ value = $admins }
    }
}
$paramFile = Join-Path ([IO.Path]::GetTempPath()) "fabric-capacity-params-$([guid]::NewGuid()).json"
$paramObject | ConvertTo-Json -Depth 10 | Set-Content -Path $paramFile -Encoding utf8

Write-Step "Previewing Fabric capacity '$($cfg.CAPACITY_NAME)' deployment"
az deployment group what-if `
    --resource-group $cfg.RESOURCE_GROUP `
    --template-file $bicepPath `
    --parameters "@$paramFile" `
    --no-pretty-print `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Capacity deployment preview failed for '$($cfg.CAPACITY_NAME)'." }
Write-Ok 'Capacity deployment preview succeeded.'

Write-Step "Deploying Fabric capacity '$($cfg.CAPACITY_NAME)' (SKU $($cfg.CAPACITY_SKU))"
$deployment = az deployment group create `
    --resource-group $cfg.RESOURCE_GROUP `
    --template-file $bicepPath `
    --parameters "@$paramFile" `
    --query properties.outputs `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "Capacity deployment failed for '$($cfg.CAPACITY_NAME)'." }

Remove-Item $paramFile -ErrorAction SilentlyContinue

Write-Ok "Capacity provisioned: $($deployment.capacityResourceId.value)"
Write-Host '    Note: it can take a few minutes for the capacity to appear in the Fabric REST /capacities list.' -ForegroundColor DarkGray
