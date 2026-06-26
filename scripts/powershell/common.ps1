# =============================================================================
# common.ps1 — shared helpers for the Fabric-as-Code PowerShell scripts.
# Dot-source this from each numbered script:  . "$PSScriptRoot/common.ps1"
# Requires: PowerShell 7+ (pwsh), Azure CLI (az).
# =============================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$FabricApiBase = 'https://api.fabric.microsoft.com/v1'
$FabricResource = 'https://api.fabric.microsoft.com'

# ---------------------------------------------------------------------------
# Load configuration from .env at the repo root into a hashtable + env vars.
# ---------------------------------------------------------------------------
function Import-FabricEnv {
    param(
        [string] $EnvPath = (Join-Path $PSScriptRoot '../../.env')
    )

    if (-not (Test-Path $EnvPath)) {
        throw "Config file '$EnvPath' not found. Copy .env.example to .env and fill it in."
    }

    $config = @{}
    foreach ($line in Get-Content $EnvPath) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '=') { continue }

        $key, $value = $trimmed -split '=', 2
        $key = $key.Trim()
        $value = $value.Trim().Trim('"').Trim("'")
        $config[$key] = $value
        Set-Item -Path "Env:$key" -Value $value
    }

    Write-Host "Loaded configuration from $EnvPath" -ForegroundColor DarkGray
    return $config
}

# ---------------------------------------------------------------------------
# Acquire an access token for a given resource via the Azure CLI.
# Works for both interactive logins and service-principal logins.
# ---------------------------------------------------------------------------
function Get-AccessToken {
    param(
        [Parameter(Mandatory)] [string] $Resource
    )
    $token = az account get-access-token --resource $Resource --query accessToken -o tsv
    if (-not $token) { throw "Failed to obtain access token for $Resource." }
    return $token
}

function Get-FabricToken { return Get-AccessToken -Resource $FabricResource }

# ---------------------------------------------------------------------------
# Thin wrapper around Invoke-RestMethod for the Fabric REST API, with
# long-running-operation (LRO) handling. Many create operations return 202 +
# an Operation-Location header that must be polled until Succeeded.
# ---------------------------------------------------------------------------
function Invoke-FabricApi {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,        # e.g. "/workspaces"
        [object] $Body,
        [Parameter(Mandatory)] [string] $Token
    )

    $headers = @{
        Authorization  = "Bearer $Token"
        'Content-Type' = 'application/json'
    }
    $uri = "$FabricApiBase$Path"
    $jsonBody = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 50 } else { $null }

    $response = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -Body $jsonBody -SkipHttpErrorCheck

    if ($response.StatusCode -eq 202) {
        # Long-running operation: poll the operation status endpoint when present.
        $opUrl = $response.Headers['Operation-Location']
        if ($opUrl -is [array]) { $opUrl = $opUrl[0] }
        if ([string]::IsNullOrWhiteSpace($opUrl)) {
            # Some 202 responses (e.g. assignToCapacity) complete without a
            # pollable operation URL. Treat as accepted/success.
            Write-Host "  -> accepted (202, no operation url)" -ForegroundColor DarkGray
            return $null
        }
        Write-Host "  -> long-running operation accepted, polling..." -ForegroundColor DarkGray
        return Wait-FabricOperation -OperationUrl $opUrl -Token $Token
    }

    if ($response.StatusCode -ge 400) {
        throw "Fabric API $Method $Path failed ($($response.StatusCode)): $($response.Content)"
    }

    if ([string]::IsNullOrWhiteSpace($response.Content)) { return $null }
    return $response.Content | ConvertFrom-Json
}

function Wait-FabricOperation {
    param(
        [Parameter(Mandatory)] [string] $OperationUrl,
        [Parameter(Mandatory)] [string] $Token,
        [int] $TimeoutSeconds = 600
    )
    $headers = @{ Authorization = "Bearer $Token" }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $op = Invoke-RestMethod -Method Get -Uri $OperationUrl -Headers $headers
        switch ($op.status) {
            'Succeeded' {
                # Fetch the operation result if a result endpoint is exposed.
                try {
                    $result = Invoke-RestMethod -Method Get -Uri "$OperationUrl/result" -Headers $headers
                    return $result
                } catch { return $op }
            }
            'Failed'    { throw "Operation failed: $($op | ConvertTo-Json -Depth 10)" }
            default     { Start-Sleep -Seconds 5 }
        }
    }
    throw "Operation timed out after $TimeoutSeconds seconds."
}

# ---------------------------------------------------------------------------
# Resolve a Fabric capacity's GUID id from its Azure resource name.
# The assignToCapacity API needs the Fabric object id (GUID), not the ARM name.
# ---------------------------------------------------------------------------
function Get-FabricCapacityId {
    param(
        [Parameter(Mandatory)] [string] $CapacityName,
        [Parameter(Mandatory)] [string] $Token
    )
    $caps = Invoke-FabricApi -Method Get -Path '/capacities' -Token $Token
    $match = $caps.value | Where-Object { $_.displayName -ieq $CapacityName }
    if (-not $match) {
        throw "Capacity '$CapacityName' not found / not visible to this identity. Ensure the identity is a capacity admin."
    }
    return @($match)[0].id
}

# ---------------------------------------------------------------------------
# Resolve a workspace id by display name (idempotent create helpers use this).
# ---------------------------------------------------------------------------
function Get-WorkspaceIdByName {
    param(
        [Parameter(Mandatory)] [string] $WorkspaceName,
        [Parameter(Mandatory)] [string] $Token
    )
    $ws = Invoke-FabricApi -Method Get -Path '/workspaces' -Token $Token
    $match = $ws.value | Where-Object { $_.displayName -ieq $WorkspaceName }
    if ($match) { return @($match)[0].id }
    return $null
}

function ConvertTo-Base64 {
    param([Parameter(Mandatory)] [string] $Text)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "    [ok] $Message" -ForegroundColor Green }
