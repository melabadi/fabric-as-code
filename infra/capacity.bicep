// =============================================================================
// capacity.bicep
// -----------------------------------------------------------------------------
// Provisions a Microsoft Fabric capacity (Microsoft.Fabric/capacities).
// Deploy at resource-group scope:
//
//   az deployment group create \
//     --resource-group <rg> \
//     --template-file infra/capacity.bicep \
//     --parameters capacityName=<name> skuName=F2 \
//                  adminMembers='["admin@contoso.com"]'
//
// Docs: https://learn.microsoft.com/azure/templates/microsoft.fabric/capacities
// =============================================================================

@description('Globally unique Fabric capacity name (3-63 chars, lowercase letters/numbers).')
@minLength(3)
@maxLength(63)
param capacityName string

@description('Azure region for the capacity. Must be a region where Fabric is available.')
param location string = resourceGroup().location

@description('Fabric SKU. F2 is the smallest. Scale up/down later without re-creating.')
@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
  'F32'
  'F64'
  'F128'
  'F256'
  'F512'
  'F1024'
  'F2048'
])
param skuName string = 'F2'

@description('Capacity administrators: array of user UPNs and/or service principal object IDs.')
param adminMembers array

@description('Optional tags applied to the capacity resource.')
param tags object = {
  managedBy: 'fabric-as-code'
  environment: 'demo'
}

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: adminMembers
    }
  }
}

@description('The Azure Resource Manager resource ID of the capacity.')
output capacityResourceId string = fabricCapacity.id

@description('The capacity name (used by Fabric REST when assigning a workspace).')
output capacityName string = fabricCapacity.name

@description('The region the capacity was deployed to.')
output location string = fabricCapacity.location
