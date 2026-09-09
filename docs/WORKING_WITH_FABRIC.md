# Working from code and the Fabric UI

Use the repository as the desired state for shared environments. The Terraform path keeps daily authoring and automated deployment in two different workspaces on the same capacity.

| Workspace role | Daily use | Definition owner |
| --- | --- | --- |
| Git authoring workspace | Fabric UI authoring, **Update from Git**, and **Commit to Git** | `fabric-git/` on the connected branch |
| CI/CD deployment workspace | Validation of the merged result; no direct authoring | Terraform deploys the same `fabric-git/` definitions |

## Expected surfaces

| Surface | Expected result |
| --- | --- |
| CI/CD deployment workspace | Terraform owns items from the selected deployment profile. |
| Git authoring workspace | Fabric Git owns supported items synchronized from the connected branch. |
| Connected Git folder | The repository's [`fabric-git/`](../fabric-git) directory. |

The Fabric UI shows synchronized Fabric items rather than raw repository files.
After connection and initialization, supported native definitions under
`fabric-git/` appear in the authoring workspace; the standalone README remains
visible only in GitHub.

## One definition source, two workspace owners

Do not let Terraform and Fabric Git integration update the same item definition in the same workspace.

| Delivery path | Target workspace | Definition source |
| --- | --- | --- |
| Fabric Git integration | Interactive authoring workspace | `fabric-git/` on the connected branch |
| Terraform deployment | Repeatable CI/CD workspace | The same committed `fabric-git/` files |

Terraform enforces the names and lifecycle of all nine CI/CD items. For the Lakehouse, Notebook, and Data Pipeline, it consumes the native definitions under [`fabric-git/`](../fabric-git/). Target-specific Notebook and workspace IDs are rendered in memory and never committed as duplicate files.

## Daily workflow

1. In the Git workspace, run **Update from Git** before starting work.
2. Author and test changes in the Fabric UI, then use **Commit to Git**. Native Fabric Git files remain under [`fabric-git/`](../fabric-git/).
3. Review those same `fabric-git/` changes in a pull request when using a branch workflow.
4. Merge into `main`; the `Deploy Fabric` workflow deploys the same definitions to the separate CI/CD workspace.
5. Validate the deployed items in the CI/CD workspace. Do not patch that workspace in place.

The Git workspace and CI/CD workspace may share a capacity, but they must have different workspace IDs. Terraform never deploys its item resources into the Git workspace, and `fabric_workspace_git` never connects the CI/CD workspace.

## Deploy from this repository

The committed variable files deploy the same Terraform resources with environment-specific values. Replace their placeholder tenant, subscription, capacity name, and administrator values first.

```powershell
terraform -chdir=terraform init -reconfigure -backend-config="path=$env:LOCALAPPDATA/fabric-as-code/dev/terraform.tfstate"
terraform -chdir=terraform validate
terraform -chdir=terraform plan -var-file=environments/dev.tfvars -out=dev.tfplan
terraform -chdir=terraform apply dev.tfplan
```

The guarded runner performs the same flow, rejects deletes, and keeps state and backups separate by environment:

```powershell
pwsh ./scripts/powershell/deploy-terraform.ps1 `
  -Environment dev `
  -VarFile ./terraform/environments/dev.tfvars
```

For the REST/Bicep scripts, keep one ignored `.env` file per environment and select it without copying files:

```powershell
$env:FABRIC_CONFIG_FILE = (Resolve-Path ./.env.dev)
pwsh ./scripts/powershell/deploy-all.ps1
```

```bash
FABRIC_CONFIG_FILE="$PWD/.env.dev" ./scripts/bash/deploy-all.sh
```

Never reuse a Terraform state file between environments. Capacity names must also be globally unique. The guarded runner refuses an old unscoped state file until it is moved into the confirmed environment directory.

## Adopt items created in the UI

Use existing-workspace mode from [`terraform.tfvars.example`](../terraform/terraform.tfvars.example):

1. Set `provision_platform = false` and `manage_workspaces = true`, then provide the CI/CD target as `workspace_id` and the Git authoring target as `git_workspace_id`.
2. Set the ID of every matching UI-created item that Terraform should adopt.
3. Leave an item ID as `null` only when Terraform should create that item.
4. Run `terraform plan` and confirm the result contains imports or creates, never replacement of an established item.

The two workspace import blocks adopt those live workspaces into state. Terraform rejects identical role IDs, and all item import IDs remain scoped to the CI/CD workspace.

The import ID is assembled as `<workspace-id>/<item-id>`. An ID from another workspace must never be reused.

## Author in the Fabric UI

Use the dedicated Git authoring workspace and this sequence:

1. If Fabric Git is enabled, **Update from Git** before editing.
2. Make and test the change in the UI. Publish Environment changes when the UI requires it.
3. Capture the change with **Commit to Git**; the native files under [`fabric-git/`](../fabric-git/) are the Terraform deployment source too.
4. Open a pull request and review the generated definition change.
5. Merge, run a Terraform plan for the target environment, and deploy through CI.
6. Verify the deployed item in the target Fabric workspace; do not patch production in place.

Fabric Git directions are important:

- **Commit to Git** sends workspace changes to the branch and can include selected items.
- **Update from Git** applies the connected branch to the workspace and considers the whole branch.
- If the same item changed on both sides, resolve the conflict deliberately. **Accept incoming** makes Git win; **Keep current** retains the workspace version so it can be committed.

Updates are not atomic, so inspect the status if an update fails partway through. Avoid changing `.platform` logical IDs because recreated items receive new Fabric IDs and invalidate Terraform state and cross-item references.

## Promotion rules

- Treat production workspaces as deployment-only.
- Pause UI editing while Terraform or a Git update is running.
- Never rename or delete a Terraform-managed item in the UI.
- Review every plan; the guarded runner refuses plans containing deletes.
- Back up or migrate state before changing runners.
- If emergency UI changes are unavoidable, export and commit them before the next deployment.

Prefer the optional Terraform `git_integration` object when Git connection lifecycle belongs in the same state. It targets only `git_workspace_id` and initializes with `PreferRemote`. [`07-git-integration.ps1`](../scripts/powershell/07-git-integration.ps1) remains a single-workspace REST fallback for the numbered script flow.

See [REST API usage](REST_API_USAGE.md) for the exact provider and direct-call boundary.