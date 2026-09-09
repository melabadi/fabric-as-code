# 1. Fabric capacity

The capacity stage creates the Azure resource that supplies Fabric compute, then
resolves the separate Fabric object GUID required by workspace assignment.

## Code map

| Responsibility | Implementation |
| --- | --- |
| Select full-platform or existing-capacity mode | [`terraform/main.tf`](../../terraform/main.tf) |
| Create `Microsoft.Fabric/capacities` and resolve its Fabric GUID | [`terraform/modules/capacity/main.tf`](../../terraform/modules/capacity/main.tf) |
| Define capacity inputs | [`terraform/modules/capacity/variables.tf`](../../terraform/modules/capacity/variables.tf) |
| Return the ARM resource ID and Fabric GUID | [`terraform/modules/capacity/outputs.tf`](../../terraform/modules/capacity/outputs.tf) |
| Supply environment values | [`terraform/environments/`](../../terraform/environments) |
| Resume an existing paused capacity before refresh | [`scripts/powershell/set-capacity-state.ps1`](../../scripts/powershell/set-capacity-state.ps1) |

## Deployment flow

1. `provision_platform = true` creates the resource group and calls the capacity
   module. Existing-capacity mode skips creation and uses `fabric_capacity_id`.
2. `azurerm_fabric_capacity` creates the F-SKU Azure resource with the configured
   administrators and tags.
3. `data.fabric_capacity` looks up the capacity by display name through the
   Fabric provider because Fabric workspace assignment needs the object GUID,
   not the Azure Resource Manager resource ID.
4. The root passes that GUID to both workspace module instances.

## Inputs and outputs

The environment file supplies `resource_group`, `location`, `capacity_name`,
`capacity_sku`, and `capacity_admins`. The module returns:

- `capacity_resource_id`: Azure Resource Manager resource ID.
- `capacity_guid`: Fabric control-plane object GUID used by workspaces.

The deployment wrapper activates an existing paused capacity before Terraform
refreshes Fabric resources. A capacity created during the same apply doesn't
need that pre-step.

## Verify

```powershell
terraform -chdir=terraform validate
terraform -chdir=terraform test -no-color
terraform -chdir=terraform output capacity_resource_id
```

In existing-capacity mode, `capacity_resource_id` is intentionally `null`
because that Azure resource remains outside this root state.

## Learn more

- [AzureRM `azurerm_fabric_capacity` resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/fabric_capacity)
- [Fabric `fabric_capacity` data source](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/data-sources/capacity)
- [Microsoft.Fabric capacities ARM/Bicep reference](https://learn.microsoft.com/azure/templates/microsoft.fabric/capacities)
- [Microsoft Fabric capacity concepts](https://learn.microsoft.com/fabric/enterprise/licenses)