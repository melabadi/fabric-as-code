#requires -Version 7.0
param(
    [string] $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    [string] $Location = $env:AZURE_LOCATION,
    [string] $RunnerNetworkResourceGroup = $env:RUNNER_NETWORK_RESOURCE_GROUP,
    [string] $FirewallPolicyName = $env:RUNNER_FIREWALL_POLICY_NAME,
    [string] $FirewallRuleCollectionGroupName = $env:RUNNER_FIREWALL_RULE_COLLECTION_GROUP_NAME,
    [string] $WorkspaceId = $env:FABRIC_WORKSPACE_ID,
    [string] $WarehouseId = $env:FABRIC_WAREHOUSE_ID,
    [string] $WarehouseName = $env:FABRIC_WAREHOUSE_NAME,
    [string] $StateStorageAccount = $env:TF_STATE_STORAGE_ACCOUNT,
    [string] $ManageWorkspaceFirewall = $env:FABRIC_MANAGE_WORKSPACE_FIREWALL,
    [string] $DeploymentEgressIp = $env:FABRIC_DEPLOYMENT_EGRESS_IP,
    [string] $WorkspaceCmkKeyIdentifier = $env:FABRIC_WORKSPACE_CMK_KEY_IDENTIFIER
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$requiredValues = [ordered]@{
    SubscriptionId                  = $SubscriptionId
    Location                        = $Location
    RunnerNetworkResourceGroup      = $RunnerNetworkResourceGroup
    FirewallPolicyName              = $FirewallPolicyName
    FirewallRuleCollectionGroupName = $FirewallRuleCollectionGroupName
    WorkspaceId                     = $WorkspaceId
    WarehouseName                   = $WarehouseName
    StateStorageAccount             = $StateStorageAccount
    ManageWorkspaceFirewall         = $ManageWorkspaceFirewall
}
$missingValues = @($requiredValues.GetEnumerator() | Where-Object {
        [string]::IsNullOrWhiteSpace([string] $_.Value)
    } | ForEach-Object Key)
if ($missingValues.Count -gt 0) {
    throw "Missing required values: $($missingValues -join ', ')"
}
if ($ManageWorkspaceFirewall -notin @('true', 'false')) {
    throw 'ManageWorkspaceFirewall must be true or false.'
}

function Test-PrivateIpv4Address {
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

function Get-AzureCliToken {
    param([Parameter(Mandatory)] [string] $Resource)

    $token = az account get-access-token `
        --resource $Resource `
        --query accessToken `
        --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Unable to acquire a token for '$Resource'."
    }
    return $token
}

$blobHost = "$StateStorageAccount.blob.core.windows.net"
$blobAddresses = @([Net.Dns]::GetHostAddresses($blobHost))
if (-not @($blobAddresses | Where-Object { Test-PrivateIpv4Address $_ })) {
    throw "Private state endpoint '$blobHost' did not resolve to an RFC 1918 address."
}
Write-Host 'Private state DNS is healthy.' -ForegroundColor Green

$armToken = $null
$fabricToken = $null
$sqlToken = $null
$connection = $null
try {
    $armToken = Get-AzureCliToken -Resource 'https://management.azure.com/'
    $armHeaders = @{ Authorization = "Bearer $armToken" }

    $serviceTagUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Network/locations/$Location/serviceTags?api-version=2024-05-01"
    $tagCollection = @()
    try {
        $nextServiceTagUri = $serviceTagUri
        while (-not [string]::IsNullOrWhiteSpace($nextServiceTagUri)) {
            $serviceTags = Invoke-RestMethod `
                -Method Get `
                -Uri $nextServiceTagUri `
                -Headers $armHeaders
            $propertyNames = @($serviceTags.PSObject.Properties.Name)
            $page = if ($propertyNames -contains 'values') {
                @($serviceTags.values)
            } elseif ($propertyNames -contains 'value') {
                @($serviceTags.value)
            } else {
                throw "Service Tag Discovery returned no tag collection. Properties: $($propertyNames -join ', ')"
            }
            $tagCollection += $page
            $nextServiceTagUri = if ($propertyNames -contains 'nextLink') {
                [string] $serviceTags.nextLink
            } else {
                $null
            }
        }
    } catch {
        Write-Warning "Service Tag Discovery isn't visible to this identity. $($_.Exception.Message)"
    }

    if ($tagCollection.Count -eq 0) {
        Write-Warning "Service-tag catalog validation skipped. Grant Microsoft.Network/locations/serviceTags/read at subscription scope to enable it."
    } else {
        foreach ($requiredTag in @(
                'AzureActiveDirectory'
                'AzureResourceManager'
                'PowerBI'
                'Sql'
            )) {
            $tag = @($tagCollection | Where-Object {
                    [string] $_.name -ieq $requiredTag
                })
            $prefixCount = if ($tag.Count -eq 1) {
                @($tag[0].properties.addressPrefixes).Count
            } else {
                0
            }
            if ($tag.Count -ne 1 -or $prefixCount -eq 0) {
                throw "Required Azure service tag '$requiredTag' is unavailable."
            }
            Write-Host "${requiredTag}: $prefixCount prefixes; change $($tag[0].properties.changeNumber)."
        }
    }

    $ruleCollectionGroupUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RunnerNetworkResourceGroup/providers/Microsoft.Network/firewallPolicies/$FirewallPolicyName/ruleCollectionGroups/${FirewallRuleCollectionGroupName}?api-version=2024-10-01"
    $ruleCollectionGroup = Invoke-RestMethod `
        -Method Get `
        -Uri $ruleCollectionGroupUri `
        -Headers $armHeaders
    if ($ruleCollectionGroup.properties.provisioningState -ne 'Succeeded') {
        throw "Firewall rule collection group is '$($ruleCollectionGroup.properties.provisioningState)'."
    }

    $allowNetworkRules = @(
        foreach ($collection in @($ruleCollectionGroup.properties.ruleCollections)) {
            if ($collection.ruleCollectionType -eq 'FirewallPolicyFilterRuleCollection' -and
                $collection.action.type -eq 'Allow') {
                @($collection.rules | Where-Object ruleType -eq 'NetworkRule')
            }
        }
    )
    $httpsDestinations = @($allowNetworkRules | Where-Object {
            @($_.ipProtocols) -contains 'TCP' -and
            @($_.destinationPorts) -contains '443'
        } | ForEach-Object destinationAddresses | Select-Object -Unique)
    foreach ($requiredTag in @('AzureActiveDirectory', 'AzureResourceManager', 'PowerBI')) {
        if ($httpsDestinations -notcontains $requiredTag) {
            throw "Firewall policy doesn't allow '$requiredTag' on TCP 443."
        }
    }

    $tdsDestinations = @($allowNetworkRules | Where-Object {
            @($_.ipProtocols) -contains 'TCP' -and
            @($_.destinationPorts) -contains '1433'
        } | ForEach-Object destinationAddresses | Select-Object -Unique)
    foreach ($requiredTag in @('PowerBI', 'Sql')) {
        if ($tdsDestinations -notcontains $requiredTag) {
            throw "Firewall policy doesn't allow '$requiredTag' on TCP 1433."
        }
    }
    Write-Host 'Azure Firewall contains the required Fabric service-tag rules.' -ForegroundColor Green

    $fabricToken = Get-AzureCliToken -Resource 'https://api.fabric.microsoft.com'
    $fabricHeaders = @{ Authorization = "Bearer $fabricToken" }
    $workspaceUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId"
    $workspace = Invoke-RestMethod -Method Get -Uri $workspaceUri -Headers $fabricHeaders
    Write-Host "Fabric REST is healthy for workspace '$($workspace.displayName)'." -ForegroundColor Green

    if (-not [string]::IsNullOrWhiteSpace($WorkspaceCmkKeyIdentifier)) {
        $encryption = Invoke-RestMethod `
            -Method Get `
            -Uri "$workspaceUri/encryption" `
            -Headers $fabricHeaders
        $encryptionStatus = [string] $encryption.encryptionDetail.encryptionStatus
        $activeKey = ([string] $encryption.encryptionDetail.keyIdentifier).TrimEnd('/')
        $expectedKey = $WorkspaceCmkKeyIdentifier.TrimEnd('/')
        if ($encryptionStatus -ne 'Active') {
            throw "Fabric workspace CMK status is '$encryptionStatus', not Active."
        }
        if (-not [string]::Equals($activeKey, $expectedKey, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Fabric workspace CMK '$activeKey' does not match '$expectedKey'."
        }
        Write-Host 'Fabric workspace CMK is active and matches the configured key.' -ForegroundColor Green
    }

    if ($ManageWorkspaceFirewall -eq 'true') {
        if ([string]::IsNullOrWhiteSpace($DeploymentEgressIp)) {
            throw 'DeploymentEgressIp is required when workspace firewall management is enabled.'
        }
        $policy = Invoke-RestMethod `
            -Method Get `
            -Uri "$workspaceUri/networking/communicationPolicy" `
            -Headers $fabricHeaders
        $firewall = Invoke-RestMethod `
            -Method Get `
            -Uri "$workspaceUri/networking/communicationPolicy/inbound/firewall" `
            -Headers $fabricHeaders
        if ($policy.inbound.publicAccessRules.defaultAction -ne 'Deny') {
            throw "Fabric workspace public access default action isn't Deny."
        }
        $matchingRules = @($firewall.rules | Where-Object value -eq $DeploymentEgressIp)
        if ($matchingRules.Count -eq 0) {
            throw "Fabric workspace doesn't allow deployment egress IP '$DeploymentEgressIp'."
        }
        Write-Host 'Fabric workspace inbound allowlisting is enforced.' -ForegroundColor Green
    } else {
        Write-Warning "Fabric workspace inbound allowlisting isn't enforced; default public access may remain Allow."
    }

    if ([string]::IsNullOrWhiteSpace($WarehouseId)) {
        $items = Invoke-RestMethod -Method Get -Uri "$workspaceUri/items" -Headers $fabricHeaders
        $warehouses = @($items.value | Where-Object {
                $_.type -eq 'Warehouse' -and $_.displayName -eq $WarehouseName
            })
        if ($warehouses.Count -ne 1) {
            throw "Expected one Warehouse named '$WarehouseName'; found $($warehouses.Count)."
        }
        $WarehouseId = $warehouses[0].id
    }

    $warehouse = Invoke-RestMethod `
        -Method Get `
        -Uri "$workspaceUri/warehouses/$WarehouseId" `
        -Headers $fabricHeaders
    $server = [string] $warehouse.properties.connectionString
    if ([string]::IsNullOrWhiteSpace($server)) {
        throw 'Fabric did not return the Warehouse connection string.'
    }

    $sqlToken = Get-AzureCliToken -Resource 'https://database.windows.net/'
    $connected = $false
    for ($attempt = 1; $attempt -le 3 -and -not $connected; $attempt++) {
        try {
            $connectionString = "Server=$server;Database=$WarehouseName;Encrypt=True;TrustServerCertificate=False;Connect Timeout=60;"
            $connection = [Data.SqlClient.SqlConnection]::new($connectionString)
            $connection.AccessToken = $sqlToken
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = 'SELECT 1'
            $command.CommandTimeout = 30
            if ([int] $command.ExecuteScalar() -ne 1) {
                throw 'Warehouse connectivity query returned an unexpected result.'
            }
            $connected = $true
        } catch {
            if ($attempt -eq 3) {
                throw
            }
            Write-Warning "Warehouse attempt $attempt failed; retrying. $($_.Exception.Message)"
            [Threading.Thread]::Sleep(5000 * $attempt)
        } finally {
            if ($null -ne $connection) {
                $connection.Dispose()
                $connection = $null
            }
        }
    }
    Write-Host "Warehouse TDS is healthy for '$WarehouseName'." -ForegroundColor Green
} finally {
    Clear-Variable armToken,fabricToken,sqlToken -ErrorAction SilentlyContinue
}