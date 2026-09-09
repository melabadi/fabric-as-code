# =============================================================================
# Assign, rotate, or reset a Fabric workspace customer-managed key and wait for
# the public workspace encryption API to reach the requested terminal state.
# Deployment guide: ../../docs/deployment/03-workspace-settings.md
# Learn more: https://learn.microsoft.com/fabric/security/workspace-customer-managed-keys
# =============================================================================
param(
    [Parameter(Mandatory)] [guid] $WorkspaceId,
    [Parameter(Mandatory)] [ValidateSet('Assign', 'Reset')] [string] $Mode,
    [AllowEmptyString()] [string] $KeyIdentifier = '',
    [ValidateRange(60, 7200)] [int] $TimeoutSeconds = 3300
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-NormalizedKeyIdentifier {
    param([Parameter(Mandatory)] [string] $Identifier)

    $keyUri = $null
    if (-not [Uri]::TryCreate($Identifier, [UriKind]::Absolute, [ref] $keyUri) -or
        $keyUri.Scheme -ne 'https' -or
        $keyUri.Host -notmatch '^[a-z0-9-]+\.(vault\.azure\.net|managedhsm\.azure\.net)$' -or
        -not [string]::IsNullOrEmpty($keyUri.Query) -or
        -not [string]::IsNullOrEmpty($keyUri.Fragment)) {
        throw 'KeyIdentifier must be an HTTPS Azure Key Vault or Managed HSM key URI.'
    }

    $segments = @($keyUri.AbsolutePath.Trim('/') -split '/')
    if ($segments.Count -ne 2 -or $segments[0] -ne 'keys' -or
        $segments[1] -notmatch '^[A-Za-z0-9-]+$') {
        throw 'KeyIdentifier must be versionless and use the form https://<vault>/keys/<key-name>.'
    }

    return "https://$($keyUri.Host)/keys/$($segments[1])"
}

function Test-SameKeyIdentifier {
    param(
        [AllowNull()] [string] $Left,
        [AllowNull()] [string] $Right
    )

    return [string]::Equals(
        ([string] $Left).TrimEnd('/'),
        ([string] $Right).TrimEnd('/'),
        [StringComparison]::OrdinalIgnoreCase
    )
}

if ($Mode -eq 'Assign') {
    if ([string]::IsNullOrWhiteSpace($KeyIdentifier)) {
        throw 'KeyIdentifier is required when Mode is Assign.'
    }
    $KeyIdentifier = Get-NormalizedKeyIdentifier -Identifier $KeyIdentifier
} elseif (-not [string]::IsNullOrWhiteSpace($KeyIdentifier)) {
    throw 'KeyIdentifier must be empty when Mode is Reset.'
}

$token = az account get-access-token `
    --resource https://api.fabric.microsoft.com `
    --query accessToken `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire a Fabric API token from the current Azure CLI session.'
}

$baseUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/encryption"
$headers = @{
    Authorization  = "Bearer $token"
    'Content-Type' = 'application/json'
}
$targetStatus = if ($Mode -eq 'Assign') { 'Active' } else { 'Disabled' }

try {
    $current = Invoke-RestMethod -Method Get -Uri $baseUri -Headers $headers
    $currentStatus = [string] $current.encryptionDetail.encryptionStatus
    $currentKey = [string] $current.encryptionDetail.keyIdentifier

    if ($currentStatus -eq $targetStatus -and
        ($Mode -eq 'Reset' -or (Test-SameKeyIdentifier $currentKey $KeyIdentifier))) {
        Write-Host "Fabric workspace '$WorkspaceId' encryption is already configured." -ForegroundColor Green
        return
    }
    $requestedTransitionInProgress = (
        ($Mode -eq 'Assign' -and
            $currentStatus -eq 'EnableInProgress' -and
            (Test-SameKeyIdentifier $currentKey $KeyIdentifier)) -or
        ($Mode -eq 'Reset' -and $currentStatus -eq 'DisableInProgress')
    )
    if ($currentStatus -in @('EnableInProgress', 'DisableInProgress') -and
        -not $requestedTransitionInProgress) {
        throw "Workspace encryption is already transitioning with status '$currentStatus'."
    }

    if ($currentStatus -notin @('EnableInProgress', 'DisableInProgress')) {
        if ($Mode -eq 'Assign') {
            $body = @{ keyIdentifier = $KeyIdentifier } | ConvertTo-Json -Compress
            Invoke-RestMethod -Method Post -Uri "$baseUri/assign" -Headers $headers -Body $body | Out-Null
        } else {
            Invoke-RestMethod -Method Post -Uri "$baseUri/reset" -Headers $headers | Out-Null
        }
    }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $responseHeaders = $null
        $state = Invoke-RestMethod `
            -Method Get `
            -Uri $baseUri `
            -Headers $headers `
            -ResponseHeadersVariable responseHeaders
        $status = [string] $state.encryptionDetail.encryptionStatus
        $activeKey = [string] $state.encryptionDetail.keyIdentifier

        if ($status -eq 'Failed') {
            throw "Fabric workspace '$WorkspaceId' encryption failed."
        }
        if ($status -eq $targetStatus -and
            ($Mode -eq 'Reset' -or (Test-SameKeyIdentifier $activeKey $KeyIdentifier))) {
            Write-Host "Fabric workspace '$WorkspaceId' encryption reached '$targetStatus'." -ForegroundColor Green
            return
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "Timed out waiting for workspace encryption to reach '$targetStatus'; current status is '$status'."
        }

        $retryAfter = 15
        if ($null -ne $responseHeaders -and $responseHeaders.ContainsKey('Retry-After')) {
            $parsedRetryAfter = 0
            $retryAfterHeader = @($responseHeaders['Retry-After'])[0]
            if ([int]::TryParse([string] $retryAfterHeader, [ref] $parsedRetryAfter)) {
                $retryAfter = [Math]::Min([Math]::Max($parsedRetryAfter, 5), 300)
            }
        }
        Start-Sleep -Seconds $retryAfter
    } while ($true)
} finally {
    Remove-Variable token, headers -ErrorAction SilentlyContinue
}