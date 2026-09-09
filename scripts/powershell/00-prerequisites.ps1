# =============================================================================
# 00-prerequisites.ps1 — verify required tooling is installed and logged in.
# =============================================================================
. "$PSScriptRoot/common.ps1"

Write-Step 'Checking prerequisites'

function Test-Command {
    param([string] $Name, [string] $InstallHint)
    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        Write-Ok "$Name found"
    } else {
        throw "$Name not found. $InstallHint"
    }
}

Test-Command -Name 'az'      -InstallHint 'Install Azure CLI: https://aka.ms/azcli'
Test-Command -Name 'pwsh'    -InstallHint 'Install PowerShell 7+: https://aka.ms/powershell'

# sqlcmd is only needed for stored-procedure deployment (step 06).
if (Get-Command 'sqlcmd' -ErrorAction SilentlyContinue) {
    Write-Ok 'sqlcmd found (needed for stored procedures)'
} else {
    Write-Host '    [warn] sqlcmd not found. Install go-sqlcmd for step 06: https://aka.ms/go-sqlcmd' -ForegroundColor Yellow
}

# Verify an Azure login exists.
$account = az account show 2>$null | ConvertFrom-Json
if ($account) {
    Write-Ok "Logged in as $($account.user.name) (sub: $($account.name))"
} else {
    Write-Host '    [warn] Not logged in. Run 01-login.ps1 next.' -ForegroundColor Yellow
}

Write-Host 'Prerequisite check complete.' -ForegroundColor Green
