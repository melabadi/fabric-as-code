# =============================================================================
# Validate one environment tfvars file against the root variable contract
# without configuring providers, credentials, or a Terraform backend.
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $VarFile,
    [Parameter(Mandatory)] [string] $ExpectedEnvironment,
    [string] $VariablesFile = (Join-Path $PSScriptRoot '../../terraform/variables.tf')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($ExpectedEnvironment -cnotmatch '^[a-z0-9-]+$') {
    throw 'ExpectedEnvironment must contain only lowercase letters, numbers, and hyphens.'
}
if (-not (Get-Command terraform -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'Terraform is not installed or is not available on PATH.'
}

$varFilePath = (Resolve-Path $VarFile).Path
$variablesFilePath = (Resolve-Path $VariablesFile).Path
$validationDirectory = Join-Path ([IO.Path]::GetTempPath()) "fabric-tfvars-$ExpectedEnvironment-$PID-$([guid]::NewGuid())"
$ambientTerraformVariables = @{}
foreach ($variable in Get-ChildItem Env:TF_VAR_*) {
    $ambientTerraformVariables[$variable.Name] = $variable.Value
}
New-Item -ItemType Directory -Path $validationDirectory -Force | Out-Null

try {
    foreach ($variableName in $ambientTerraformVariables.Keys) {
        Remove-Item "Env:$variableName"
    }

    Copy-Item $variablesFilePath "$validationDirectory/variables.tf"
    Copy-Item $varFilePath "$validationDirectory/environment.tfvars"

    Push-Location $validationDirectory
    try {
        & terraform init -backend=false -input=false 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw 'Terraform tfvars initialization failed.'
        }
    } finally {
        Pop-Location
    }

    Push-Location $validationDirectory
    try {
        $planArguments = @(
            'plan'
            '-input=false'
            '-refresh=false'
            '-lock=false'
            '-no-color'
            '-out=validation.tfplan'
            '-var-file=environment.tfvars'
        )
        $planOutput = (& terraform @planArguments 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform tfvars validation failed. $planOutput"
        }
        if ($planOutput -match '(?m)^Warning:') {
            throw "Terraform tfvars contains unsupported or deprecated settings. $planOutput"
        }

        $showArguments = @('show', '-json', 'validation.tfplan')
        $planJson = (& terraform @showArguments 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw 'Terraform could not read the tfvars validation plan.'
        }
        $plan = $planJson | ConvertFrom-Json -Depth 100
    } finally {
        Pop-Location
    }

    $deploymentEnvironment = [string] $plan.variables.deployment_environment.value
    if ($deploymentEnvironment -cne $ExpectedEnvironment) {
        throw "deployment_environment '$deploymentEnvironment' must match '$ExpectedEnvironment'."
    }

    Write-Host "Terraform variable file '$varFilePath' is valid for '$ExpectedEnvironment'." -ForegroundColor Green
} finally {
    foreach ($variableName in $ambientTerraformVariables.Keys) {
        Set-Item "Env:$variableName" $ambientTerraformVariables[$variableName]
    }
    Remove-Item $validationDirectory -Recurse -Force -ErrorAction SilentlyContinue
}