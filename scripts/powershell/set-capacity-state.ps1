# =============================================================================
# set-capacity-state.ps1 - resume or pause an existing Fabric capacity.
# Optionally records the initial state so CI can restore it after deployment.
# =============================================================================
param(
    [Parameter(Mandatory)]
    [ValidateSet('Active', 'Paused')]
    [string] $DesiredState,

    [string] $RecordInitialStatePath,

    [switch] $AllowMissing,

    [string] $SubscriptionId,

    [string] $ResourceGroup,

    [string] $CapacityName
)

. "$PSScriptRoot/common.ps1"

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or
    [string]::IsNullOrWhiteSpace($ResourceGroup) -or
    [string]::IsNullOrWhiteSpace($CapacityName)) {
    $cfg = Import-FabricEnv
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { $SubscriptionId = $cfg.SUBSCRIPTION_ID }
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $ResourceGroup = $cfg.RESOURCE_GROUP }
    if ([string]::IsNullOrWhiteSpace($CapacityName)) { $CapacityName = $cfg.CAPACITY_NAME }
}

$requiredValues = [ordered]@{
    SubscriptionId = $SubscriptionId
    ResourceGroup  = $ResourceGroup
    CapacityName   = $CapacityName
}
$missingValues = @($requiredValues.GetEnumerator() | Where-Object {
        [string]::IsNullOrWhiteSpace([string] $_.Value)
    } | ForEach-Object Key)
if ($missingValues.Count -gt 0) {
    throw "Missing capacity identifiers: $($missingValues -join ', ')."
}

$apiVersion = '2023-11-01'
$resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Fabric/capacities/$CapacityName"
$managementEndpoint = 'https://management.azure.com'

$armToken = az account get-access-token `
    --resource https://management.azure.com/ `
    --query accessToken `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($armToken)) {
    throw 'Unable to acquire an Azure Resource Manager token from the current Azure CLI session.'
}
$headers = @{ Authorization = "Bearer $armToken" }

function Get-CapacityState {
    $response = Invoke-WebRequest `
        -Method Get `
        -Uri "$managementEndpoint${resourceId}?api-version=$apiVersion" `
        -Headers $headers `
        -SkipHttpErrorCheck
    if ($response.StatusCode -eq 404 -and $AllowMissing) {
        return $null
    }
    if ($response.StatusCode -ne 200) {
        throw "Could not read Fabric capacity '$CapacityName' (HTTP $($response.StatusCode)): $($response.Content)"
    }

    $capacity = $response.Content | ConvertFrom-Json
    $state = [string] $capacity.properties.state
    if ([string]::IsNullOrWhiteSpace($state)) {
        throw "Could not read the state of Fabric capacity '$CapacityName'."
    }
    return $state.Trim()
}

$initialState = Get-CapacityState
if ($null -eq $initialState) {
    Write-Host "Capacity '$CapacityName' does not exist yet; Terraform will create it." -ForegroundColor DarkGray
    return
}
if ($RecordInitialStatePath) {
    @{ state = $initialState } |
        ConvertTo-Json |
        Set-Content -Path $RecordInitialStatePath -Encoding utf8
}

if ($initialState -eq $DesiredState) {
    Write-Ok "Capacity '$CapacityName' is already $DesiredState."
    return
}

$action = if ($DesiredState -eq 'Active') { 'resume' } else { 'suspend' }
Write-Step "$action Fabric capacity '$CapacityName'"
$response = Invoke-WebRequest `
    -Method Post `
    -Uri "$managementEndpoint${resourceId}/${action}?api-version=$apiVersion" `
    -Headers $headers `
    -SkipHttpErrorCheck
if ($response.StatusCode -notin @(200, 202)) {
    throw "Failed to $action Fabric capacity '$CapacityName' (HTTP $($response.StatusCode)): $($response.Content)"
}

for ($attempt = 0; $attempt -lt 60; $attempt++) {
    Start-Sleep -Seconds 5
    $currentState = Get-CapacityState
    if ($currentState -eq $DesiredState) {
        Write-Ok "Capacity '$CapacityName' is $DesiredState."
        return
    }
}

throw "Fabric capacity '$CapacityName' did not reach state '$DesiredState' within 5 minutes."