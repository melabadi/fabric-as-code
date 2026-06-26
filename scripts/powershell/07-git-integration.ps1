# =============================================================================
# 07-git-integration.ps1 — (optional) connect the workspace to Git so the
# items become source-controlled. Supports Azure DevOps and GitHub providers.
#
# This step is OPTIONAL. The deploy-all orchestration skips it unless the
# GIT_PROVIDER variable is set in .env. Add the following keys to .env to use:
#
#   GIT_PROVIDER="AzureDevOps"          # or "GitHub"
#   GIT_ORG="my-ado-org"                # ADO org / GitHub owner
#   GIT_PROJECT="my-ado-project"        # ADO only
#   GIT_REPO="my-repo"
#   GIT_BRANCH="main"
#   GIT_DIRECTORY="/fabric"             # folder in the repo to sync items into
#
# Docs: https://learn.microsoft.com/rest/api/fabric/core/git
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv
$token = Get-FabricToken

if (-not $cfg.ContainsKey('GIT_PROVIDER') -or -not $cfg.GIT_PROVIDER) {
    Write-Host 'GIT_PROVIDER not set in .env — skipping Git integration (optional step).' -ForegroundColor Yellow
    return
}

$statePath = Join-Path $PSScriptRoot '../../.state.json'
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$workspaceId = $state.workspaceId

Write-Step "Connecting workspace to $($cfg.GIT_PROVIDER)"

$gitProviderDetails = if ($cfg.GIT_PROVIDER -ieq 'GitHub') {
    @{
        gitProviderType = 'GitHub'
        ownerName       = $cfg.GIT_ORG
        repositoryName  = $cfg.GIT_REPO
        branchName      = $cfg.GIT_BRANCH
        directoryName   = $cfg.GIT_DIRECTORY
    }
} else {
    @{
        gitProviderType   = 'AzureDevOps'
        organizationName  = $cfg.GIT_ORG
        projectName       = $cfg.GIT_PROJECT
        repositoryName    = $cfg.GIT_REPO
        branchName        = $cfg.GIT_BRANCH
        directoryName     = $cfg.GIT_DIRECTORY
    }
}

# 1) Connect the workspace to the Git repository.
Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/git/connect" `
    -Body @{ gitProviderDetails = $gitProviderDetails } -Token $token | Out-Null
Write-Ok 'Workspace connected to Git.'

# 2) Initialize the connection (sync direction depends on what already exists).
Invoke-FabricApi -Method Post -Path "/workspaces/$workspaceId/git/initializeConnection" `
    -Body @{ initializationStrategy = 'PreferWorkspace' } -Token $token | Out-Null
Write-Ok 'Git connection initialized (PreferWorkspace).'

Write-Host 'Workspace is now source-controlled. Use the Fabric UI or git/commitToGit + git/updateFromGit APIs to sync.' -ForegroundColor Green
