# =============================================================================
# 01-login.ps1 — authenticate to Azure / Entra ID.
# Uses a service principal if SP_CLIENT_ID/SP_CLIENT_SECRET are set in .env,
# otherwise falls back to interactive login. Sets the active subscription.
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv

Write-Step 'Authenticating to Azure'

if ($cfg.SP_CLIENT_ID -and $cfg.SP_CLIENT_SECRET) {
    Write-Host '    Using service principal login (non-interactive).' -ForegroundColor DarkGray
    az login --service-principal `
        --username $cfg.SP_CLIENT_ID `
        --password $cfg.SP_CLIENT_SECRET `
        --tenant   $cfg.TENANT_ID `
        --output none
} else {
    Write-Host '    Using interactive login.' -ForegroundColor DarkGray
    az login --tenant $cfg.TENANT_ID --output none
}

az account set --subscription $cfg.SUBSCRIPTION_ID --output none
Write-Ok "Active subscription set to $($cfg.SUBSCRIPTION_ID)"

# Smoke-test that we can mint a Fabric token with this identity.
$null = Get-FabricToken
Write-Ok 'Successfully acquired a Microsoft Fabric API token.'
