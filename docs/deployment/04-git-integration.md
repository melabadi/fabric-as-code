# 4. Connect Git integration

Git integration connects only the authoring workspace to the existing GitHub or
Azure DevOps repository. Terraform continues to deploy items independently to
the CI/CD workspace.

## Code map

| Responsibility | Implementation |
| --- | --- |
| Define and validate repository settings | [`git_integration`](../../terraform/variables.tf) |
| Select caller-specific configured credentials | [`terraform_data.git_credentials`](../../terraform/main.tf) and [`set-fabric-git-credentials.ps1`](../../scripts/powershell/set-fabric-git-credentials.ps1) |
| Connect and initialize the authoring workspace | [`fabric_workspace_git.this`](../../terraform/main.tf) |
| Store Fabric-native definitions | [`fabric-git/`](../../fabric-git) |
| Explain edit ownership | [`docs/WORKING_WITH_FABRIC.md`](../WORKING_WITH_FABRIC.md) |

## Deployment flow

1. Create and share a Fabric Git connection outside this Terraform stack.
2. Put its non-secret connection GUID and repository coordinates in the
   environment's `git_integration` object.
3. For `ConfiguredConnection`, the pre-plan helper updates the current caller's
   `myGitCredentials` selection. Credentials themselves remain in Fabric.
4. `fabric_workspace_git` connects the authoring workspace and defaults to
   `PreferRemote`, importing the repository's `/fabric-git` definitions.
5. Authors update from Git, edit in Fabric, and commit supported definitions
   back to the repository. A merge to `main` triggers Terraform deployment to
   the separate CI/CD workspace.

## Required values

GitHub uses `provider_type = "GitHub"`, `owner_name`, `repository_name`,
`branch_name`, `directory_name`, and a configured `connection_id`. Azure DevOps
uses `organization_name` and `project_name`; it can use `Automatic` or
`ConfiguredConnection` credentials.

The repository must already exist. This deployment owns the workspace
connection, not repository creation or PAT rotation.

## Verify

```powershell
terraform -chdir=terraform output git_connection_state
```

The expected terminal value is `ConnectedAndInitialized`. In Fabric, verify the
source control pane points to the configured branch and `/fabric-git` directory.

## Learn more

- [Fabric provider `fabric_workspace_git` resource](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace_git)
- [Fabric provider overview](https://registry.terraform.io/providers/microsoft/fabric/latest/docs)
- [Overview of Fabric Git integration](https://learn.microsoft.com/fabric/cicd/git-integration/intro-to-git-integration)
- [Connect a workspace to Git](https://learn.microsoft.com/fabric/cicd/git-integration/git-get-started)
- [Fabric Git REST API](https://learn.microsoft.com/rest/api/fabric/core/git)
