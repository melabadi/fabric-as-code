# =============================================================================
# deploy-terraform.ps1 - guarded Terraform deployment for local or hosted runners.
# Uses a private Azure Blob backend with native locking and versioning, rejects
# destructive plans, applies the reviewed plan, and requires convergence.
# =============================================================================
param(
    [string] $TerraformDirectory = (Join-Path $PSScriptRoot '../../terraform'),
    [string] $Environment,
    [string] $VarFile,
    [string] $BackendResourceGroup = $env:TF_BACKEND_RESOURCE_GROUP,
    [string] $BackendStorageAccount = $env:TF_BACKEND_STORAGE_ACCOUNT,
    [string] $BackendContainer = $env:TF_BACKEND_CONTAINER,
    [string] $BackendKey = $env:TF_BACKEND_KEY,
    [switch] $PlanOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    throw 'Terraform is not installed or is not available on PATH.'
}

$terraformPath = (Resolve-Path $TerraformDirectory).Path
if ([string]::IsNullOrWhiteSpace($Environment)) {
    $Environment = $env:TF_VAR_deployment_environment
} elseif (-not [string]::IsNullOrWhiteSpace($env:TF_VAR_deployment_environment) -and
    $Environment -cne $env:TF_VAR_deployment_environment) {
    throw "Environment '$Environment' does not match TF_VAR_deployment_environment '$env:TF_VAR_deployment_environment'."
}
if ([string]::IsNullOrWhiteSpace($Environment)) {
    throw 'Environment is required. Pass -Environment or set TF_VAR_deployment_environment.'
}
$Environment = $Environment.Trim()
if ($Environment -and $Environment -cnotmatch '^[a-z0-9-]+$') {
    throw 'Environment must contain only lowercase letters, numbers, and hyphens.'
}
$varFilePath = if ($VarFile) { (Resolve-Path $VarFile).Path } else { $null }
$varFileArguments = if ($varFilePath) { @("-var-file=$varFilePath") } else { @() }
if ($varFilePath) {
    & "$PSScriptRoot/validate-terraform-var-file.ps1" `
        -VarFile $varFilePath `
        -ExpectedEnvironment $Environment
}
$variableOverrideArguments = @()
if (Test-Path Env:TF_VAR_fabric_workspace_firewall_ip) {
    $firewallIpOverride = [string] $env:TF_VAR_fabric_workspace_firewall_ip
    if (-not [string]::IsNullOrWhiteSpace($firewallIpOverride)) {
        $variableOverrideArguments += "-var=fabric_workspace_firewall_ip=$firewallIpOverride"
    }
}

if ([string]::IsNullOrWhiteSpace($BackendKey)) {
    $BackendKey = "$Environment/terraform.tfstate"
}

$backendValues = @{
    TF_BACKEND_RESOURCE_GROUP  = $BackendResourceGroup
    TF_BACKEND_STORAGE_ACCOUNT = $BackendStorageAccount
    TF_BACKEND_CONTAINER       = $BackendContainer
}
$missingBackendValues = @($backendValues.GetEnumerator() | Where-Object {
        [string]::IsNullOrWhiteSpace($_.Value)
    } | ForEach-Object { $_.Key })
if ($missingBackendValues.Count -gt 0) {
    throw "Missing Terraform backend configuration: $($missingBackendValues -join ', ')"
}

function Test-PrivateIpAddress {
    param([Parameter(Mandatory)] [Net.IPAddress] $Address)

    if ($Address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }
    $bytes = $Address.GetAddressBytes()
    return (
        $bytes[0] -eq 10 -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
    )
}

$blobEndpoint = "$BackendStorageAccount.blob.core.windows.net"
$blobAddresses = @([Net.Dns]::GetHostAddresses($blobEndpoint))
if ($blobAddresses.Count -eq 0 -or -not @($blobAddresses | Where-Object {
            Test-PrivateIpAddress -Address $_
        })) {
    throw "Terraform backend '$blobEndpoint' does not resolve to a private IP. Run from the configured GitHub VNet or a connected network."
}

$tempRoot = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    [IO.Path]::GetTempPath()
} else {
    $env:RUNNER_TEMP
}
$deploymentWorkingDirectory = Join-Path $tempRoot "fabric-deployment-$Environment-$PID"
$planPath = Join-Path $deploymentWorkingDirectory 'fabric.tfplan'
New-Item -ItemType Directory -Path $deploymentWorkingDirectory -Force | Out-Null

function Invoke-Terraform {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int[]] $AllowedExitCodes = @(0)
    )

    & terraform @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $AllowedExitCodes) {
        throw "terraform $($Arguments[0]) failed with exit code $exitCode."
    }
    return $exitCode
}

function Get-TerraformConfiguration {
        $expression = 'jsonencode({ tenant_id = var.tenant_id, subscription_id = var.subscription_id, deployment_environment = var.deployment_environment, provision_platform = var.provision_platform, resource_group = var.resource_group, capacity_name = var.capacity_name, workspace_id = var.provision_platform ? null : var.workspace_id, git_workspace_id = var.provision_platform ? null : var.git_workspace_id, fabric_workspace_firewall_ip = var.fabric_workspace_firewall_ip, git_integration = var.git_integration, workspace_encryption = var.workspace_encryption })'
        $consoleArguments = @('console', '-no-color') + $varFileArguments + $variableOverrideArguments
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command terraform -CommandType Application).Source
    $startInfo.WorkingDirectory = (Get-Location).Path
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $consoleArguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'Failed to start Terraform console.'
        }
        $process.StandardInput.WriteLine($expression)
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $consoleOutput = $stdoutTask.GetAwaiter().GetResult()
        $consoleError = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Failed to evaluate the selected Terraform configuration. $consoleError"
        }
        if (-not [string]::IsNullOrWhiteSpace($consoleError)) {
            throw "Terraform reported configuration diagnostics. $consoleError"
        }
    } finally {
        $process.Dispose()
    }

    try {
        $encodedJson = ($consoleOutput.Trim() | ConvertFrom-Json)
        return $encodedJson | ConvertFrom-Json
    } catch {
        throw "Terraform returned an invalid configuration payload. $($_.Exception.Message)"
    }
}

function Assert-AzureContext {
    param([Parameter(Mandatory)] [object] $Configuration)

    $account = az account show --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $null -eq $account) {
        throw 'Unable to read the current Azure CLI context.'
    }
    if ([string] $account.tenantId -ne [string] $Configuration.tenant_id) {
        throw "Azure CLI tenant does not match tenant_id in '$varFilePath'."
    }
    if ([string] $account.id -ne [string] $Configuration.subscription_id) {
        throw "Azure CLI subscription does not match subscription_id in '$varFilePath'."
    }
}

function Get-TerraformStateOutputs {
    $outputJson = (& terraform output -json 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to read workspace IDs from the current Terraform state.'
    }
    if ([string]::IsNullOrWhiteSpace($outputJson)) {
        return [pscustomobject]@{}
    }

    return $outputJson | ConvertFrom-Json
}

function Get-TerraformOutputGuid {
    param(
        [Parameter(Mandatory)] [object] $Outputs,
        [Parameter(Mandatory)] [string] $Name
    )

    $property = $Outputs.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value.value) { return $null }

    $parsedId = [guid]::Empty
    if ([guid]::TryParse([string] $property.Value.value, [ref] $parsedId)) {
        return $parsedId
    }
    return $null
}

function Resolve-WorkspaceGuid {
    param(
        [Parameter(Mandatory)] [object] $Outputs,
        [Parameter(Mandatory)] [string] $OutputName,
        [AllowNull()] [AllowEmptyString()] [string] $ConfiguredValue
    )

    $workspaceId = Get-TerraformOutputGuid -Outputs $Outputs -Name $OutputName
    if ($null -ne $workspaceId) { return $workspaceId }

    $configuredId = [guid]::Empty
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredValue) -and
        [guid]::TryParse($ConfiguredValue, [ref] $configuredId)) {
        return $configuredId
    }
    return $null
}

function Sync-FabricWorkspaceFirewall {
    param(
        [Parameter(Mandatory)] [object] $Outputs,
        [Parameter(Mandatory)] [string] $IpAddress,
        [AllowNull()] [string] $CicdWorkspaceId,
        [AllowNull()] [string] $GitWorkspaceId
    )

    $workspaceIds = @(
        foreach ($workspace in @(
                @{ Output = 'cicd_workspace_id'; ConfiguredValue = $CicdWorkspaceId }
                @{ Output = 'git_workspace_id'; ConfiguredValue = $GitWorkspaceId }
            )) {
            $workspaceId = Resolve-WorkspaceGuid `
                -Outputs $Outputs `
                -OutputName $workspace.Output `
                -ConfiguredValue $workspace.ConfiguredValue
            if ($null -ne $workspaceId) { $workspaceId }
        }
    ) | Select-Object -Unique

    foreach ($workspaceId in $workspaceIds) {
        & "$PSScriptRoot/set-fabric-workspace-firewall.ps1" `
            -WorkspaceId $workspaceId `
            -IpAddress $IpAddress
    }
}

function Sync-FabricGitCredentials {
    param(
        [Parameter(Mandatory)] [object] $Outputs,
        [AllowNull()] [object] $Integration,
        [AllowNull()] [string] $ConfiguredGitWorkspaceId
    )

    if ($null -eq $Integration) {
        return
    }
    $credentialsSourceProperty = $Integration.PSObject.Properties['credentials_source']
    $credentialsSource = if (
        $null -eq $credentialsSourceProperty -or
        [string]::IsNullOrWhiteSpace([string] $credentialsSourceProperty.Value)
    ) {
        'ConfiguredConnection'
    } else {
        [string] $credentialsSourceProperty.Value
    }
    if ($credentialsSource -ne 'ConfiguredConnection') { return }
    $connectionIdProperty = $Integration.PSObject.Properties['connection_id']
    if ($null -eq $connectionIdProperty -or
        [string]::IsNullOrWhiteSpace([string] $connectionIdProperty.Value)) {
        throw 'ConfiguredConnection Git integration requires connection_id.'
    }

    $gitWorkspaceId = Resolve-WorkspaceGuid `
        -Outputs $Outputs `
        -OutputName 'git_workspace_id' `
        -ConfiguredValue $ConfiguredGitWorkspaceId
    if ($null -eq $gitWorkspaceId) {
        return
    }

    & "$PSScriptRoot/set-fabric-git-credentials.ps1" `
        -WorkspaceId $gitWorkspaceId `
        -ConnectionId ([string] $connectionIdProperty.Value)
}

function Sync-FabricWorkspaceEncryption {
    param(
        [Parameter(Mandatory)] [object] $Outputs,
        [AllowNull()] [object] $Policies,
        [AllowNull()] [string] $CicdWorkspaceId,
        [AllowNull()] [string] $GitWorkspaceId
    )

    if ($null -eq $Policies) { return }
    foreach ($policyProperty in $Policies.PSObject.Properties) {
        $workspaceName = $policyProperty.Name
        $workspace = if ($workspaceName -eq 'cicd') {
            @{ Output = 'cicd_workspace_id'; ConfiguredValue = $CicdWorkspaceId }
        } else {
            @{ Output = 'git_workspace_id'; ConfiguredValue = $GitWorkspaceId }
        }
        $workspaceId = Resolve-WorkspaceGuid `
            -Outputs $Outputs `
            -OutputName $workspace.Output `
            -ConfiguredValue $workspace.ConfiguredValue
        if ($null -eq $workspaceId) { continue }

        $policy = $policyProperty.Value
        $mode = if ([bool] $policy.enabled) { 'Assign' } else { 'Reset' }
        $keyIdentifier = if ($mode -eq 'Assign') { [string] $policy.key_identifier } else { '' }
        & "$PSScriptRoot/set-fabric-workspace-encryption.ps1" `
            -WorkspaceId $workspaceId `
            -Mode $mode `
            -KeyIdentifier $keyIdentifier
    }
}

function Test-FabricApiConnectivity {
    $token = az account get-access-token `
        --resource https://api.fabric.microsoft.com `
        --query accessToken `
        --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Unable to acquire a Fabric API token through the runner egress policy.'
    }
    try {
        Invoke-RestMethod `
            -Method Get `
            -Uri 'https://api.fabric.microsoft.com/v1/workspaces' `
            -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Host 'Fabric REST API is reachable from the runner.' -ForegroundColor Green
    } finally {
        Remove-Variable token -ErrorAction SilentlyContinue
    }
}

Push-Location $terraformPath
try {
    $backendArguments = @(
        'init',
        '-reconfigure',
        '-input=false',
        "-backend-config=resource_group_name=$BackendResourceGroup",
        "-backend-config=storage_account_name=$BackendStorageAccount",
        "-backend-config=container_name=$BackendContainer",
        "-backend-config=key=$BackendKey",
        '-backend-config=use_azuread_auth=true'
    )
    if ($env:GITHUB_ACTIONS -eq 'true') {
        foreach ($requiredName in @('ARM_CLIENT_ID', 'ARM_TENANT_ID', 'ARM_SUBSCRIPTION_ID')) {
            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($requiredName))) {
                throw "$requiredName is required for the GitHub OIDC Terraform backend."
            }
        }
        $backendArguments += @(
            '-backend-config=use_oidc=true',
            "-backend-config=client_id=$env:ARM_CLIENT_ID",
            "-backend-config=tenant_id=$env:ARM_TENANT_ID",
            "-backend-config=subscription_id=$env:ARM_SUBSCRIPTION_ID"
        )
    } else {
        $backendArguments += '-backend-config=use_cli=true'
        if (-not [string]::IsNullOrWhiteSpace($env:TF_VAR_tenant_id)) {
            $backendArguments += "-backend-config=tenant_id=$env:TF_VAR_tenant_id"
        }
    }

    Invoke-Terraform -Arguments $backendArguments | Out-Null
    Invoke-Terraform -Arguments @('fmt', '-check', '-recursive') | Out-Null
    Invoke-Terraform -Arguments @('validate') | Out-Null
    Invoke-Terraform -Arguments @('test', '-no-color') | Out-Null

    $configuration = Get-TerraformConfiguration
    if ([string] $configuration.deployment_environment -cne $Environment) {
        throw "Environment '$Environment' does not match deployment_environment '$($configuration.deployment_environment)' in '$varFilePath'."
    }
    Assert-AzureContext -Configuration $configuration

    if (-not $PlanOnly -and -not [string]::IsNullOrWhiteSpace([string] $configuration.capacity_name)) {
        & "$PSScriptRoot/set-capacity-state.ps1" `
            -DesiredState Active `
            -AllowMissing:([bool] $configuration.provision_platform) `
            -SubscriptionId ([string] $configuration.subscription_id) `
            -ResourceGroup ([string] $configuration.resource_group) `
            -CapacityName ([string] $configuration.capacity_name)
    }

    $stateOutputs = Get-TerraformStateOutputs
    if (-not $PlanOnly) {
        if (-not [string]::IsNullOrWhiteSpace([string] $configuration.fabric_workspace_firewall_ip)) {
            Sync-FabricWorkspaceFirewall `
                -Outputs $stateOutputs `
                -IpAddress ([string] $configuration.fabric_workspace_firewall_ip) `
                -CicdWorkspaceId ([string] $configuration.workspace_id) `
                -GitWorkspaceId ([string] $configuration.git_workspace_id)
        }
        Sync-FabricGitCredentials `
            -Outputs $stateOutputs `
            -Integration $configuration.git_integration `
            -ConfiguredGitWorkspaceId ([string] $configuration.git_workspace_id)
    }
    Test-FabricApiConnectivity

    $planArguments = @(
        'plan',
        '-input=false',
        '-lock-timeout=5m',
        "-out=$planPath",
        '-detailed-exitcode',
        '-no-color'
    ) + $varFileArguments + $variableOverrideArguments
    $planExitCode = Invoke-Terraform -Arguments $planArguments -AllowedExitCodes @(0, 2)

    $plan = (& terraform show -json $planPath) | ConvertFrom-Json -Depth 100
    if ($LASTEXITCODE -ne 0) { throw 'Failed to render the Terraform plan as JSON.' }

    $destructiveChanges = @($plan.resource_changes | Where-Object {
            $actions = @($_.change.actions)
            $isStateOnlyChange = (
                $_.address -eq 'module.sql[0].terraform_data.stored_procs' -or
                $_.address -like 'fabric_workspace_role_assignment.this*' -or
                $_.address -like 'terraform_data.git_credentials*' -or
                $_.address -like 'terraform_data.workspace_encryption*' -or
                $_.address -like 'terraform_data.workspace_firewall*'
            )
            $actions -contains 'delete' -and -not $isStateOnlyChange
        })
    if ($destructiveChanges.Count -gt 0) {
        $addresses = $destructiveChanges.address -join ', '
        throw "Terraform plan contains destructive changes: $addresses"
    }

    if ($PlanOnly) {
        Write-Host "Terraform plan for '$Environment' passed policy checks; apply was skipped." -ForegroundColor Green
        return
    }

    Sync-FabricWorkspaceEncryption `
        -Outputs $stateOutputs `
        -Policies $configuration.workspace_encryption `
        -CicdWorkspaceId ([string] $configuration.workspace_id) `
        -GitWorkspaceId ([string] $configuration.git_workspace_id)

    if ($planExitCode -eq 2) {
        Invoke-Terraform -Arguments @(
            'apply',
            '-input=false',
            '-auto-approve',
            $planPath
        ) | Out-Null
    } else {
        Write-Host 'Terraform plan has no changes; apply skipped.' -ForegroundColor Green
    }

    $convergenceArguments = @(
        'plan',
        '-input=false',
        '-lock-timeout=5m',
        '-detailed-exitcode',
        '-no-color'
    ) + $varFileArguments + $variableOverrideArguments
    $convergenceExitCode = Invoke-Terraform -Arguments $convergenceArguments -AllowedExitCodes @(0, 2)
    if ($convergenceExitCode -ne 0) {
        throw 'Terraform did not converge to a zero-change plan after apply.'
    }

    Write-Host 'Terraform deployment converged successfully.' -ForegroundColor Green
} finally {
    Pop-Location
    Remove-Item $deploymentWorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
}