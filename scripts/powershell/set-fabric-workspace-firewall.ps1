# =============================================================================
# Preserve existing Fabric workspace IP rules, upsert the deployment egress IP,
# and deny public requests from every address not on the resulting allowlist.
# Deployment guide: ../../docs/deployment/03-workspace-settings.md
# Official API contract:
# https://learn.microsoft.com/fabric/security/security-workspace-level-firewall-set-up#configure-workspace-ip-firewall-rules
# =============================================================================
param(
    [Parameter(Mandatory)] [guid] $WorkspaceId,
    [Parameter(Mandatory)] [string] $IpAddress,
    [string] $RuleName = 'github-actions-egress'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$parsedIp = $null
if (-not [Net.IPAddress]::TryParse($IpAddress, [ref] $parsedIp) -or
    $parsedIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw "IpAddress '$IpAddress' must be a valid IPv4 address."
}
if ([string]::IsNullOrWhiteSpace($RuleName)) {
    throw 'RuleName must not be empty.'
}

$token = az account get-access-token `
    --resource https://api.fabric.microsoft.com `
    --query accessToken `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire a Fabric API token from the current Azure CLI session.'
}

$baseUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/networking/communicationPolicy"
$firewallUri = "$baseUri/inbound/firewall"
$headers = @{
    Authorization  = "Bearer $token"
    'Content-Type' = 'application/json'
}

try {
    $current = Invoke-RestMethod -Method Get -Uri $firewallUri -Headers $headers
    $rules = @($current.rules | Where-Object { $_.displayName -ne $RuleName })
    $rules += [pscustomobject]@{
        displayName = $RuleName
        value       = $parsedIp.ToString()
    }

    $firewallBody = @{ rules = $rules } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Put -Uri $firewallUri -Headers $headers -Body $firewallBody | Out-Null

    $policyBody = @{
        inbound = @{
            publicAccessRules = @{
                defaultAction = 'Deny'
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Put -Uri $baseUri -Headers $headers -Body $policyBody | Out-Null

    $verified = Invoke-RestMethod -Method Get -Uri $firewallUri -Headers $headers
    $matchingRule = @($verified.rules | Where-Object {
            $_.displayName -eq $RuleName -and $_.value -eq $parsedIp.ToString()
        })
    if ($matchingRule.Count -ne 1) {
        throw "Fabric did not persist IP rule '$RuleName' for workspace '$WorkspaceId'."
    }

    Write-Host "Fabric workspace '$WorkspaceId' allows deployment egress IP '$IpAddress'." -ForegroundColor Green
} finally {
    Remove-Variable token, headers -ErrorAction SilentlyContinue
}