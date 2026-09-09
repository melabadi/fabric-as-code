# Workspace module

This module creates a Fabric workspace and assigns it to a Fabric capacity in one provider-managed resource.

Browse the [workspace deployment guide](../../../docs/deployment/02-workspaces.md)
for the end-to-end call path. Learn more in the official
[`fabric_workspace` provider documentation](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace).

The `capacity_id` input is the Fabric object GUID produced by the capacity module, not the Azure Resource Manager resource ID. That reference also gives Terraform the dependency needed to create the workspace only after the capacity can be resolved through Fabric.

The root module calls this module twice whenever Terraform manages workspaces:

- `module.workspace` creates the CI/CD deployment workspace that receives Terraform-managed items.
- `module.git_workspace` creates the authoring workspace that can mirror the repository through Fabric Git.

`provision_platform = true` creates the capacity and both workspaces. On an existing capacity, `manage_workspaces = true` uses `fabric_capacity_id` and creates or imports both workspaces; supplied `workspace_id` and `git_workspace_id` drive declarative imports. The root also enables `skip_capacity_state_validation` so the deployment identity does not need the unsupported service-principal capacity-admin assignment. When workspace management is disabled, those IDs are consumed directly without adding workspace resources to state.

The root resolves every mode into role-specific locals so this reusable module stays unaware of deployment policy. Items receive only the CI/CD workspace ID, while `fabric_workspace_git` receives only the authoring workspace ID.

The root also owns cross-workspace policy: native `fabric_workspace_role_assignment` resources, optional GA workspace-CMK API markers, the workspace inbound firewall, and the authoring workspace Git connection. Keeping those controls above this module lets one policy entry target either or both role-specific workspaces without duplicating workspace creation logic.

Authentication is handled by the root Fabric provider. No credentials are accepted or stored by this module.
