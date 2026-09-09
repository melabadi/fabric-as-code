# =============================================================================
# set-fabric-git-credentials.ps1 - bind the current identity to a configured
# Fabric Git connection. Git credentials are caller-specific in Fabric.
# Deployment guide: ../../docs/deployment/04-git-integration.md
# Learn more: https://learn.microsoft.com/rest/api/fabric/core/git
# =============================================================================
param(
    [Parameter(Mandatory)] [guid] $WorkspaceId,
    [Parameter(Mandatory)] [guid] $ConnectionId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$token = az account get-access-token `
    --resource https://api.fabric.microsoft.com `
    --query accessToken `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire a Fabric API token from the current Azure CLI session.'
}

$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/git/myGitCredentials"
$headers = @{
    Authorization  = "Bearer $token"
    'Content-Type' = 'application/json'
}

try {
    $current = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    if ($current.source -eq 'ConfiguredConnection' -and $current.connectionId -eq $ConnectionId) {
        Write-Host 'Fabric Git credentials already use the configured connection.' -ForegroundColor Green
        return
    }

    $body = @{
        source       = 'ConfiguredConnection'
        connectionId = $ConnectionId
    } | ConvertTo-Json -Compress
    $updated = Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $body
    if ($updated.source -ne 'ConfiguredConnection' -or $updated.connectionId -ne $ConnectionId) {
        throw 'Fabric did not persist the configured Git connection for the current identity.'
    }
    Write-Host 'Fabric Git credentials configured for the deployment identity.' -ForegroundColor Green
} finally {
    Remove-Variable token, headers -ErrorAction SilentlyContinue
}