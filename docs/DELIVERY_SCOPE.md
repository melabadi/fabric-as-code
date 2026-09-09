# Delivery scope

This matrix is the acceptance checklist for the requested deployment. It keeps
three states distinct:

- **Delivered**: implemented in code and covered by repository validation.
- **External prerequisite**: deliberately performed outside this deployment.
- **Outside P0**: not claimed as part of the requested green scope.

## GitHub Copilot tooling

| Capability | Status | Evidence |
| --- | --- | --- |
| Project instructions | Delivered | [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) |
| Terraform-specific instructions | Delivered | [`.github/instructions/terraform.instructions.md`](../.github/instructions/terraform.instructions.md) |
| Fabric deployment agent | Delivered | [`.github/agents/fabric-deployment-reviewer.agent.md`](../.github/agents/fabric-deployment-reviewer.agent.md) |
| Deployment validation skill | Delivered | [`.github/skills/fabric-deployment-validation/SKILL.md`](../.github/skills/fabric-deployment-validation/SKILL.md) |
| Reusable validation prompt | Delivered | [`.github/prompts/validate-fabric-deployment.prompt.md`](../.github/prompts/validate-fabric-deployment.prompt.md) |
| Azure and GitHub MCP servers | Delivered | [`.vscode/mcp.json`](../.vscode/mcp.json) |

## Terraform platform and workspace

| Screenshot item | Status | Evidence and boundary |
| --- | --- | --- |
| Capacity | Delivered | [`azurerm_fabric_capacity`](../terraform/modules/capacity/main.tf) and the [capacity guide](deployment/01-capacity.md). |
| Workspace | Delivered | Separate CI/CD and Git authoring instances of [`fabric_workspace`](../terraform/modules/workspace/main.tf), documented in the [workspace guide](deployment/02-workspaces.md). |
| Policies / Security | Delivered | The [workspace settings guide](deployment/03-workspace-settings.md) covers RBAC, CMK, inbound policy, and monitoring order. |
| CMK | Delivered as reusable automation | [`terraform_data.workspace_encryption`](../terraform/main.tf) and [`set-fabric-workspace-encryption.ps1`](../scripts/powershell/set-fabric-workspace-encryption.ps1) implement assign, rotate, reset, and status polling. Customers enable it only after tenant-admin prerequisites and a P0-compatible item set exist. |
| Role assignments | Delivered | [`fabric_workspace_role_assignment.this`](../terraform/main.tf) expands customer-supplied principals across the selected workspaces. |
| Monitoring | Delivered configuration | [`terraform/runner-network/main.tf`](../terraform/runner-network/main.tf) sends Azure Firewall logs and metrics to Log Analytics. [Post-apply](../.github/workflows/deploy-fabric.yml) and [scheduled](../.github/workflows/verify-fabric-network.yml) canaries verify state DNS, network rules, Fabric REST, optional CMK/firewall, and Warehouse TDS. Customers configure an eligible VNet larger runner and private backend, then opt into the schedule with `FABRIC_ENABLE_SCHEDULED_CANARY=true`. Native Fabric Workspace monitoring remains a portal handoff. |

## Repository assignment

| Screenshot item | Status | Evidence and boundary |
| --- | --- | --- |
| Create the repository | External prerequisite | Repository creation, ownership, branch protection, and credential rotation remain outside this deployment. This avoids Terraform owning the repository that stores its own configuration. |
| Connect the repository | Delivered | [`fabric_workspace_git.this`](../terraform/main.tf) connects only the authoring workspace; [`set-fabric-git-credentials.ps1`](../scripts/powershell/set-fabric-git-credentials.ps1) selects caller-specific configured credentials. See [Git integration](deployment/04-git-integration.md). |

## Fabric items

| Screenshot item | Status | Evidence and boundary |
| --- | --- | --- |
| Warehouse | Delivered in P0 | [`fabric_warehouse.this`](../terraform/modules/items/main.tf); ordered SQL files deploy through the [SQL module](../terraform/modules/sql). |
| Lakehouse | Delivered in P0 | [`fabric_lakehouse.this`](../terraform/modules/items/main.tf) consumes [`fabric-git/lh_git_authoring_demo.Lakehouse/`](../fabric-git/lh_git_authoring_demo.Lakehouse). |
| Notebook | Delivered in P0 | [`fabric_notebook.this`](../terraform/modules/items/main.tf) consumes [`notebook-content.py`](../fabric-git/nb_git_authoring_demo.Notebook/notebook-content.py). |
| Eventhouse | Available only in the extended `all` profile | [`fabric_eventhouse.this`](../terraform/modules/items/main.tf) exists for the complete demo but is outside the screenshot's green P0 item set. |
| Power BI Report | Outside P0 | No report definition or Terraform resource is claimed by this deployment. |
| Power BI Semantic Model | Outside P0 | No semantic-model definition or Terraform resource is claimed by this deployment. |
| Eventstream | Outside P0 | No Eventstream definition or Terraform resource is claimed by this deployment. |

The full source-to-resource behavior is documented in
[Fabric files and item deployment](deployment/05-content-files.md).

## Workflows

| Screenshot item | Status | Evidence and behavior |
| --- | --- | --- |
| Deploys with tfvars | Delivered | [Deploy Fabric](../.github/workflows/deploy-fabric.yml) selects deployable files under `terraform/environments/` and passes the selected file to [`deploy-terraform.ps1`](../scripts/powershell/deploy-terraform.ps1). Each environment uses a distinct Blob state key. |
| PR of a new tfvars with deployment | Delivered as validate-on-PR, deploy-on-merge | [Validate Fabric Terraform](../.github/workflows/validate-fabric.yml) validates every added or changed environment file without credentials. After merge to `main`, [Deploy Fabric](../.github/workflows/deploy-fabric.yml) selects that same non-template tfvars file and deploys it through its matching GitHub Environment. [`test-terraform-environment-selection.ps1`](../scripts/powershell/test-terraform-environment-selection.ps1) regression-tests both selections. PRs never deploy privileged infrastructure directly. |

## Validation contract

Before merge or deployment, run:

```powershell
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
terraform -chdir=terraform test -no-color

pwsh ./scripts/powershell/validate-terraform-var-file.ps1 `
  -VarFile ./terraform/environments/dev.tfvars `
  -ExpectedEnvironment dev
```

The guarded deployment additionally rejects unexpected deletes, applies a saved
plan, and requires a zero-change convergence plan.

The pull-request workflow also runs
[`test-public-repository-hygiene.ps1`](../scripts/powershell/test-public-repository-hygiene.ps1)
to reject populated environment files, real resource GUIDs, concrete Azure or
Fabric resource URLs, internal environment markers, state/auth artifacts, and
unexpected binary deployment evidence. The generated sanitized presentation
outputs are the only allowed PDF and PPTX files.