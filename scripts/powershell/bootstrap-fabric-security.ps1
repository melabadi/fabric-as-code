#requires -Version 7.0
param(
    [Parameter(Mandatory)] [guid] $TenantId,
    [Parameter(Mandatory)] [guid] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $Location,
    [Parameter(Mandatory)] [string] $VaultName,
    [string] $KeyName = 'fabric-git-workspace',
    [string] $ViewerGroupName = 'Example Fabric Viewers',
    [string] $ViewerGroupMailNickname = 'example-fabric-viewers'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$fabricPlatformCmkAppId = '61d6811f-7544-4e75-a1e6-1c59c0383311'

function Invoke-AzJson {
    param([Parameter(Mandatory)] [string[]] $Arguments)

    $output = (& az @Arguments 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments -join ' ') failed. $output"
    }
    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }
    return $output | ConvertFrom-Json
}

$account = Invoke-AzJson @('account', 'show', '--output', 'json')
if ($account.tenantId -ne $TenantId -or $account.id -ne $SubscriptionId) {
    throw "Azure CLI must target tenant '$TenantId' and subscription '$SubscriptionId'."
}

$groups = @(Invoke-AzJson @(
        'ad', 'group', 'list',
        '--filter', "displayName eq '$ViewerGroupName'",
        '--output', 'json'
    ))
$viewerGroup = @($groups | Where-Object displayName -ceq $ViewerGroupName)
if ($viewerGroup.Count -gt 1) {
    throw "More than one Entra group is named '$ViewerGroupName'."
}
$groupCreated = $viewerGroup.Count -eq 0
if ($groupCreated) {
    $viewerGroup = Invoke-AzJson @(
        'ad', 'group', 'create',
        '--display-name', $ViewerGroupName,
        '--mail-nickname', $ViewerGroupMailNickname,
        '--output', 'json'
    )
} else {
    $viewerGroup = $viewerGroup[0]
}

$servicePrincipals = @(Invoke-AzJson @(
        'ad', 'sp', 'list',
        '--filter', "appId eq '$fabricPlatformCmkAppId'",
        '--output', 'json'
    ))
$fabricCmkServicePrincipal = @($servicePrincipals | Where-Object appId -eq $fabricPlatformCmkAppId)
if ($fabricCmkServicePrincipal.Count -gt 1) {
    throw "More than one service principal has appId '$fabricPlatformCmkAppId'."
}
$servicePrincipalCreated = $fabricCmkServicePrincipal.Count -eq 0
if ($servicePrincipalCreated) {
    $fabricCmkServicePrincipal = Invoke-AzJson @(
        'ad', 'sp', 'create',
        '--id', $fabricPlatformCmkAppId,
        '--output', 'json'
    )
} else {
    $fabricCmkServicePrincipal = $fabricCmkServicePrincipal[0]
}

$vault = $null
$vaultCreated = $false
try {
    $vault = Invoke-AzJson @(
        'keyvault', 'show',
        '--name', $VaultName,
        '--subscription', $SubscriptionId,
        '--output', 'json'
    )
} catch {
    if ($_.Exception.Message -notmatch 'ResourceNotFound|could not be found') {
        throw
    }
}

if ($null -eq $vault) {
    $vaultCreated = $true
    $vault = Invoke-AzJson @(
        'keyvault', 'create',
        '--name', $VaultName,
        '--resource-group', $ResourceGroup,
        '--location', $Location,
        '--sku', 'standard',
        '--retention-days', '90',
        '--enable-purge-protection', 'true',
        '--enable-rbac-authorization', 'false',
        '--subscription', $SubscriptionId,
        '--output', 'json'
    )
} elseif (
    $vault.location -ne $Location -or
    -not [bool] $vault.properties.enablePurgeProtection -or
    [bool] $vault.properties.enableRbacAuthorization
) {
    throw "Existing vault '$VaultName' does not match the required location, purge-protection, and access-policy settings."
}

$signedInUser = Invoke-AzJson @('ad', 'signed-in-user', 'show', '--output', 'json')
Invoke-AzJson @(
    'keyvault', 'set-policy',
    '--name', $VaultName,
    '--object-id', $signedInUser.id,
    '--key-permissions',
    'get', 'list', 'create', 'update', 'delete', 'recover', 'backup', 'restore',
    'import', 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey',
    '--subscription', $SubscriptionId,
    '--output', 'json'
) | Out-Null

Invoke-AzJson @(
    'keyvault', 'set-policy',
    '--name', $VaultName,
    '--object-id', $fabricCmkServicePrincipal.id,
    '--key-permissions', 'get', 'wrapKey', 'unwrapKey',
    '--subscription', $SubscriptionId,
    '--output', 'json'
) | Out-Null

$key = $null
$keyCreated = $false
try {
    $key = Invoke-AzJson @(
        'keyvault', 'key', 'show',
        '--vault-name', $VaultName,
        '--name', $KeyName,
        '--subscription', $SubscriptionId,
        '--output', 'json'
    )
} catch {
    if ($_.Exception.Message -notmatch 'KeyNotFound|not found') {
        throw
    }
}
if ($null -eq $key) {
    $keyCreated = $true
    $key = Invoke-AzJson @(
        'keyvault', 'key', 'create',
        '--vault-name', $VaultName,
        '--name', $KeyName,
        '--kty', 'RSA',
        '--size', '2048',
        '--subscription', $SubscriptionId,
        '--output', 'json'
    )
}

$versionlessKeyIdentifier = "https://$VaultName.vault.azure.net/keys/$KeyName"
[pscustomobject]@{
    viewerGroup = [ordered]@{
        created     = $groupCreated
        displayName = $viewerGroup.displayName
        objectId    = $viewerGroup.id
    }
    fabricPlatformCmkServicePrincipal = [ordered]@{
        appId     = $fabricPlatformCmkAppId
        created   = $servicePrincipalCreated
        objectId  = $fabricCmkServicePrincipal.id
    }
    keyVault = [ordered]@{
        created           = $vaultCreated
        location          = $vault.location
        name              = $VaultName
        purgeProtection   = [bool] $vault.properties.enablePurgeProtection
        rbacAuthorization = [bool] $vault.properties.enableRbacAuthorization
    }
    key = [ordered]@{
        created           = $keyCreated
        keyType           = $key.key.kty
        versionlessKeyUri = $versionlessKeyIdentifier
    }
} | ConvertTo-Json -Depth 6