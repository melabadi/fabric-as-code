# =============================================================================
# deploy-all.ps1 — run the full end-to-end Fabric-as-Code deployment.
# Executes each numbered step in order. Re-runnable (steps are idempotent).
#
# Usage:
#   pwsh ./scripts/powershell/deploy-all.ps1
#   pwsh ./scripts/powershell/deploy-all.ps1 -SkipStoredProcs   # if no sqlcmd
# =============================================================================
param(
    [switch] $SkipLogin,
    [switch] $SkipStoredProcs,
    [switch] $WithGit
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

Write-Host '================ Fabric-as-Code: full deployment ================' -ForegroundColor Magenta

& "$here/00-prerequisites.ps1"
if (-not $SkipLogin)       { & "$here/01-login.ps1" }
& "$here/02-provision-capacity.ps1"
& "$here/03-create-workspace.ps1"
& "$here/04-assign-capacity.ps1"
& "$here/05-deploy-items.ps1"
if (-not $SkipStoredProcs) { & "$here/06-deploy-stored-procedures.ps1" }
if ($WithGit)              { & "$here/07-git-integration.ps1" }

Write-Host '================ Deployment complete ============================' -ForegroundColor Magenta
Write-Host 'Open https://app.fabric.microsoft.com to explore the workspace.' -ForegroundColor Green
