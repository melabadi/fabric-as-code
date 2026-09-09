# Capacity module

This module creates the billable Microsoft Fabric capacity in Azure and then resolves the identifier that Fabric uses for the same capacity.

## Why two identifiers exist

The capacity crosses two control planes:

| Output | Meaning | Consumer |
| --- | --- | --- |
| `capacity_resource_id` | Full Azure Resource Manager ID for `Microsoft.Fabric/capacities` | Azure RBAC, operations, inventory, and billing |
| `capacity_guid` | Fabric object GUID returned by the Fabric API | `fabric_workspace.capacity_id` |

`azurerm_fabric_capacity` creates the Azure resource. The `fabric_capacity` data source then looks it up by display name because a workspace cannot use the ARM resource ID for capacity assignment.

## Identity requirements

The providers reuse the current Azure CLI identity. In CI that session comes from GitHub OIDC through `azure/login`. The identity needs:

- Azure permission to create or update the capacity when this module is enabled.
- Fabric visibility of the capacity. In practice, make the identity a capacity administrator through `admin_members`.

The data-source postcondition turns a missing Fabric-side lookup into a targeted error instead of allowing an empty GUID to reach the workspace module.

## Inputs and lifecycle

- `capacity_name` is globally unique and becomes the Azure resource name and Fabric display name.
- `sku_name` selects the F SKU; changing it updates capacity size through AzureRM.
- `admin_members` contains administrator UPNs or service-principal object IDs.
- `tags` carries environment and ownership metadata from the root module.

The root module instantiates this module only when `provision_platform = true`. Capacity pause and resume are operational actions outside this module; the CI helper restores the state that existed before deployment.
