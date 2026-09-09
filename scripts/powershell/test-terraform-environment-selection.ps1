#requires -Version 7.0
param(
    [string] $RepositoryRoot = (Join-Path $PSScriptRoot '../..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryPath = (Resolve-Path $RepositoryRoot).Path
$selector = Join-Path $repositoryPath 'scripts/powershell/select-terraform-environments.ps1'
$sourceVarFile = Join-Path $repositoryPath 'terraform/environments/dev.tfvars'
$testRepository = Join-Path ([IO.Path]::GetTempPath()) "fabric-selector-test-$PID-$([guid]::NewGuid())"

function Invoke-Git {
    param([Parameter(Mandatory)] [string[]] $Arguments)

    & git -C $testRepository @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
}

function Assert-SingleTarget {
    param(
        [Parameter(Mandatory)] [object] $Selection,
        [Parameter(Mandatory)] [string] $ExpectedEnvironment,
        [Parameter(Mandatory)] [string] $ExpectedVarFile
    )

    $targets = @($Selection.matrix.include)
    if (-not $Selection.has_targets -or $targets.Count -ne 1) {
        throw "Expected one selected environment; found $($targets.Count)."
    }
    if ($targets[0].environment -cne $ExpectedEnvironment -or
        $targets[0].var_file -cne $ExpectedVarFile) {
        throw "Unexpected selection: $($targets | ConvertTo-Json -Compress)."
    }
}

function Assert-NoTargets {
    param([Parameter(Mandatory)] [object] $Selection)

    if ($Selection.has_targets) {
        throw "Expected no deployable environments; found $($Selection.matrix.include | ConvertTo-Json -Compress)."
    }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $testRepository 'terraform/environments') -Force | Out-Null
    Copy-Item $sourceVarFile (Join-Path $testRepository 'terraform/environments/dev.tfvars')

    Invoke-Git @('init', '--initial-branch=main')
    Invoke-Git @('add', '.')
    Invoke-Git @('-c', 'user.name=Fabric Selector Test', '-c', 'user.email=fabric-selector@example.invalid', 'commit', '-m', 'Initial environment')
    $baseSha = (& git -C $testRepository rev-parse HEAD).Trim()

    New-Item -ItemType Directory -Path (Join-Path $testRepository 'terraform') -Force | Out-Null
    Set-Content (Join-Path $testRepository 'terraform/main.tf') '# shared Terraform change'
    Invoke-Git @('add', 'terraform/main.tf')
    Invoke-Git @('-c', 'user.name=Fabric Selector Test', '-c', 'user.email=fabric-selector@example.invalid', 'commit', '-m', 'Change shared Terraform')
    $sharedChangeSha = (& git -C $testRepository rev-parse HEAD).Trim()

    $templateOnlySelection = & $selector `
        -Mode Deploy `
        -EventName push `
        -BaseSha $baseSha `
        -HeadSha $sharedChangeSha `
        -RepositoryRoot $testRepository `
        -GitHubOutput '' `
        -PassThru
    Assert-NoTargets -Selection $templateOnlySelection
    $baseSha = $sharedChangeSha

    $newEnvironment = 'screenshot'
    $newVarFile = "terraform/environments/$newEnvironment.tfvars"
    Copy-Item $sourceVarFile (Join-Path $testRepository $newVarFile)
    $newVarFilePath = Join-Path $testRepository $newVarFile
    $newVarFileContent = Get-Content $newVarFilePath -Raw
    $newVarFileContent = $newVarFileContent -replace '(?m)^# deployment: template\r?\n', ''
    $newVarFileContent = $newVarFileContent -replace 'deployment_environment\s*=\s*"dev"', 'deployment_environment = "screenshot"'
    Set-Content $newVarFilePath $newVarFileContent -NoNewline
    Invoke-Git @('add', $newVarFile)
    Invoke-Git @('-c', 'user.name=Fabric Selector Test', '-c', 'user.email=fabric-selector@example.invalid', 'commit', '-m', 'Add deployment environment')
    $headSha = (& git -C $testRepository rev-parse HEAD).Trim()

    $validationSelection = & $selector `
        -Mode Validate `
        -EventName pull_request `
        -BaseSha $baseSha `
        -HeadSha $headSha `
        -RepositoryRoot $testRepository `
        -GitHubOutput '' `
        -PassThru
    Assert-SingleTarget `
        -Selection $validationSelection `
        -ExpectedEnvironment $newEnvironment `
        -ExpectedVarFile $newVarFile

    $deploymentSelection = & $selector `
        -Mode Deploy `
        -EventName push `
        -BaseSha $baseSha `
        -HeadSha $headSha `
        -RepositoryRoot $testRepository `
        -GitHubOutput '' `
        -PassThru
    Assert-SingleTarget `
        -Selection $deploymentSelection `
        -ExpectedEnvironment $newEnvironment `
        -ExpectedVarFile $newVarFile

    Write-Host 'New tfvars selection is valid for PR validation and post-merge deployment.' -ForegroundColor Green
} finally {
    Remove-Item $testRepository -Recurse -Force -ErrorAction SilentlyContinue
}
