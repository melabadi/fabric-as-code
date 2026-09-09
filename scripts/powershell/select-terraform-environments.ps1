# =============================================================================
# Resolve changed Terraform environment files into a GitHub Actions matrix.
# Deployment mode excludes explicit templates; validation mode checks them.
# =============================================================================
param(
    [Parameter(Mandatory)] [ValidateSet('Deploy', 'Validate')] [string] $Mode,
    [Parameter(Mandatory)] [string] $EventName,
    [string] $BaseSha,
    [string] $HeadSha,
    [string] $RequestedEnvironment,
    [string] $RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string] $GitHubOutput = $env:GITHUB_OUTPUT,
    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryPath = (Resolve-Path $RepositoryRoot).Path
$environmentFilePattern = '^terraform/environments/[^/]+\.tfvars$'
$environmentPattern = '^terraform/environments/[a-z0-9-]+\.tfvars$'
$varFiles = @()

Push-Location $repositoryPath
try {
    if ($EventName -eq 'workflow_dispatch') {
        if ($Mode -ne 'Deploy') {
            throw 'workflow_dispatch is supported only in Deploy mode.'
        }
        if ($RequestedEnvironment -cnotmatch '^[a-z0-9-]+$') {
            throw 'The selected environment must contain only lowercase letters, numbers, and hyphens.'
        }
        $varFiles = @("terraform/environments/$RequestedEnvironment.tfvars")
    } else {
        if ($HeadSha -cnotmatch '^[0-9a-fA-F]{40}$') {
            throw 'HeadSha must be a full Git commit SHA.'
        }

        $changeRecords = if ([string]::IsNullOrWhiteSpace($BaseSha) -or $BaseSha -match '^0+$') {
            @(& git diff-tree --root --no-commit-id --name-status --find-renames -r $HeadSha)
        } else {
            if ($BaseSha -cnotmatch '^[0-9a-fA-F]{40}$') {
                throw 'BaseSha must be a full Git commit SHA.'
            }
            $diffBaseSha = $BaseSha
            if ($EventName -eq 'pull_request') {
                $mergeBaseOutput = (& git merge-base $BaseSha $HeadSha 2>&1) | Out-String
                if ($LASTEXITCODE -ne 0) {
                    throw "Unable to resolve the merge base for '$BaseSha' and '$HeadSha'. $mergeBaseOutput"
                }
                $diffBaseSha = $mergeBaseOutput.Trim()
                if ($diffBaseSha -cnotmatch '^[0-9a-fA-F]{40}$') {
                    throw "Git returned an invalid merge-base SHA '$diffBaseSha'."
                }
            }
            @(& git diff --name-status --find-renames $diffBaseSha $HeadSha)
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect changed files between '$BaseSha' and '$HeadSha'."
        }

        $changedPaths = @()
        foreach ($record in $changeRecords) {
            $parts = @($record -split "`t")
            $status = $parts[0]
            if ($status.StartsWith('R')) {
                $oldPath = $parts[1]
                $newPath = $parts[2]
                if ($oldPath -cmatch $environmentFilePattern -or $newPath -cmatch $environmentFilePattern) {
                    throw "Renaming Terraform environment files is blocked because it changes the state key. Migrate state explicitly before renaming '$oldPath'."
                }
                $changedPaths += @($oldPath, $newPath)
                continue
            }

            $path = $parts[-1]
            if ($status.StartsWith('D') -and $path -cmatch $environmentFilePattern) {
                throw "Deleting Terraform environment file '$path' is blocked until its state and resources are explicitly retired."
            }
            if ($path -cmatch $environmentFilePattern -and $path -cnotmatch $environmentPattern) {
                throw "Terraform environment file '$path' must use a lowercase letters, numbers, and hyphens filename."
            }
            $changedPaths += $path
            if ($path -cmatch $environmentPattern) {
                $varFiles += $path
            }
        }

        $sharedDeploymentChanged = @($changedPaths | Where-Object {
                $_ -cmatch '^(\.github/workflows/|fabric-git/|scripts/powershell/|terraform/)' -and
                $_ -cnotmatch $environmentPattern
            }).Count -gt 0
        if ($Mode -eq 'Deploy' -and $sharedDeploymentChanged) {
            $varFiles += @(Get-ChildItem terraform/environments -Filter '*.tfvars' -File |
                    ForEach-Object { $_.FullName.Substring($repositoryPath.Length + 1).Replace('\', '/') })
        } elseif ($Mode -eq 'Validate' -and ($sharedDeploymentChanged -or $varFiles.Count -eq 0)) {
            $varFiles += 'terraform/environments/dev.tfvars'
        }
    }

    $varFiles = @($varFiles | Sort-Object -Unique | Where-Object {
            if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
                throw "Terraform variable file '$_' does not exist."
            }
            $templateOnly = @(Get-Content -LiteralPath $_ -TotalCount 20 | Where-Object {
                    $_.Trim() -ceq '# deployment: template'
                }).Count -gt 0
            if ($Mode -eq 'Deploy' -and $templateOnly -and $EventName -eq 'workflow_dispatch') {
                throw "Terraform variable file '$_' is a template and cannot be deployed."
            }
            $Mode -eq 'Validate' -or -not $templateOnly
        })

    $targets = @(
        foreach ($varFile in $varFiles) {
            if ($varFile -cnotmatch '^terraform/environments/(?<environment>[a-z0-9-]+)\.tfvars$') {
                throw "Terraform variable file '$varFile' must use terraform/environments/<environment>.tfvars."
            }
            @{
                environment = $Matches.environment
                var_file    = $varFile
            }
        }
    )
    $hasTargets = $targets.Count -gt 0
    if (-not $hasTargets) {
        $targets = @(@{ environment = 'none'; var_file = '' })
    }

    $matrix = @{ include = @($targets) } | ConvertTo-Json -Depth 5 -Compress
    if (-not [string]::IsNullOrWhiteSpace($GitHubOutput)) {
        "has_targets=$($hasTargets.ToString().ToLowerInvariant())" >> $GitHubOutput
        "matrix=$matrix" >> $GitHubOutput
    }
    if ($PassThru) {
        [pscustomobject]@{
            has_targets = $hasTargets
            matrix      = $matrix | ConvertFrom-Json
        }
    }
} finally {
    Pop-Location
}