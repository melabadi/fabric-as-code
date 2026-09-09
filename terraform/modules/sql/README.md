# SQL module

This module deploys the ordered SQL files under `fabric-git/sql/` to the managed Fabric Warehouse.

Browse the [content files deployment guide](../../../docs/deployment/05-content-files.md)
for its place in the end-to-end flow. Learn more about the bridge in the official
[`terraform_data` documentation](https://developer.hashicorp.com/terraform/language/resources/terraform-data).

## Why this is an imperative bridge

The Fabric provider exposes the Warehouse and its SQL endpoint but does not provide Terraform resources for arbitrary schemas, tables, or stored procedures. A built-in `terraform_data` resource therefore owns a narrowly scoped `local-exec` hook that calls `deploy-procs.ps1`.

The script:

1. Requests an Entra token for `https://database.windows.net/` from the current Azure CLI session.
2. Opens an encrypted .NET `SqlClient` connection to the provider-supplied Warehouse endpoint.
3. Sorts the `*.sql` files by filename.
4. Splits each file on whole-line, case-insensitive `GO` delimiters and executes the batches.

No Fabric REST request is constructed by this module. The access token stays in process memory and is not written to Terraform state.

## Replacement trigger

`triggers_replace` combines:

- The Warehouse GUID.
- The `deploy-procs.ps1` implementation hash.
- A deterministic SHA-1 digest of the sorted SQL file set and contents.

Changing the target Warehouse, the deployment script, or any SQL file replaces only the `terraform_data` state marker and reruns the script. It does not destroy a remote Azure or Fabric resource.

Terraform tracks execution of the hook, not individual database objects. SQL files must therefore be idempotent so retries and later deployments converge safely.

## Prerequisites

- PowerShell 7 or later.
- Azure CLI authenticated to the target tenant.
- Warehouse data-plane permission for the authenticated identity.
- An active Fabric capacity while the scripts execute.

The root module can disable this module with `deploy_stored_procedures = false`. During upgrades, the root `removed` block forgets the former `null_resource` marker with `destroy = false` before the built-in marker is created.