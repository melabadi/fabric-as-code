# 2. Fabric workspaces

The workspace stage creates or adopts two workspaces with separate ownership:
an authoring workspace connected to Git and a CI/CD workspace whose items are
managed by Terraform.

## Code map

| Responsibility | Implementation |
| --- | --- |
| Call the module once per workspace role | [`terraform/main.tf`](../../terraform/main.tf) |
| Create and assign one workspace | [`terraform/modules/workspace/main.tf`](../../terraform/modules/workspace/main.tf) |
| Define module inputs and validation | [`terraform/modules/workspace/variables.tf`](../../terraform/modules/workspace/variables.tf) |
| Return the workspace GUID | [`terraform/modules/workspace/outputs.tf`](../../terraform/modules/workspace/outputs.tf) |
| Adopt existing workspace IDs | [`terraform/imports.tf`](../../terraform/imports.tf) |
| Publish stable role-specific IDs | [`terraform/outputs.tf`](../../terraform/outputs.tf) |

## Deployment flow

1. The capacity stage returns a Fabric capacity object GUID.
2. `module.workspace` creates or imports the CI/CD deployment workspace.
3. `module.git_workspace` creates or imports the Git authoring workspace.
4. Root locals normalize both creation modes into `cicd_workspace_id` and
   `git_workspace_id`.
5. Items receive only the CI/CD workspace ID. Git integration receives only the
   authoring workspace ID.

This split prevents Terraform item deployment and Fabric Git synchronization
from owning the same definitions in the same workspace.

## Inputs and outputs

Managed workspace mode uses `workspace_name`, `workspace_description`,
`git_workspace_name`, `git_workspace_description`, and `fabric_capacity_id`.
Existing externally managed mode uses `workspace_id` and, when Git integration
is enabled, `git_workspace_id`.

The root exports `cicd_workspace_id` and `git_workspace_id` for deployment,
monitoring, and operational scripts.

## Verify

```powershell
terraform -chdir=terraform output cicd_workspace_id
terraform -chdir=terraform output git_workspace_id
```

In Fabric, confirm both workspaces are assigned to the expected capacity and
that only the authoring workspace shows a Git connection.

## Learn more

- [Fabric provider `fabric_workspace` resource](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace)
- [Fabric provider overview](https://registry.terraform.io/providers/microsoft/fabric/latest/docs)
- [Create a Microsoft Fabric workspace](https://learn.microsoft.com/fabric/fundamentals/create-workspaces)
- [Manage Fabric capacity and workspace assignments](https://learn.microsoft.com/fabric/admin/capacity-settings)
