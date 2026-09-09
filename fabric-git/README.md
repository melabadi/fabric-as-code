# Fabric Git workspace

This directory is the repository root for the dedicated Fabric Git authoring workspace. Fabric Git writes its native item folders and `.platform` metadata here.

Browse [Connect Git integration](../docs/deployment/04-git-integration.md) for
the workspace connection flow and [Fabric files and item deployment](../docs/deployment/05-content-files.md)
for the source-to-resource map. Learn more in the official
[`fabric_workspace_git` provider documentation](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace_git).

Fabric displays supported items, not arbitrary files. When this folder is
connected to an authoring workspace, Fabric synchronizes its recognized item
directories; this README itself does not create an item.

This directory is the single source of truth for all Fabric content. Fabric Git synchronizes recognized item folders with the authoring workspace, while Terraform and fallback scripts read those same definitions plus `sql/` when deploying the separate CI/CD workspace. Target-specific IDs are rendered only in memory. The plain `sql/` folder has no `.platform` file, so Fabric Git retains it in the repository without treating it as a workspace item.

To demonstrate the Git lane, create or edit a supported item in Fabric and use **Commit to Git**. To demonstrate the deployment lane, merge the resulting `fabric-git/` definitions to `main` and let GitHub Actions deploy them to the CI/CD workspace.
