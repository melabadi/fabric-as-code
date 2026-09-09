# REST API usage

This repository is provider-first. The default GitHub Actions deployment uses Terraform for every Azure and Fabric resource supported by the installed providers. Repository code constructs HTTP requests only where the operation is not a stable declarative resource lifecycle.

## Default workflow boundary

| Concern | Owner | Protocol used by repository code |
| --- | --- | --- |
| Resource group and Fabric capacity | `hashicorp/azurerm` | No direct HTTP; the provider calls Azure Resource Manager. |
| CI/CD workspace, Git authoring workspace, and optional Git connection | `microsoft/fabric` | No direct HTTP; the provider calls the Fabric API. |
| Workspace role assignments | `microsoft/fabric` | Native `fabric_workspace_role_assignment`; no direct HTTP. |
| Nine Fabric items and Notebook/Pipeline definitions | `microsoft/fabric` | No direct HTTP; the provider calls the Fabric API and handles long-running operations. |
| Capacity activation before deployment | `set-capacity-state.ps1` | Azure CLI obtains the ARM token; public Azure Resource Manager `GET`/`POST` routes read and resume the capacity. |
| Caller-specific Git credentials | `set-fabric-git-credentials.ps1` | Direct Fabric API `GET`/`PATCH` before Terraform so the OIDC identity uses the configured connection. |
| Workspace inbound IP allowlist | `terraform_data` plus `set-fabric-workspace-firewall.ps1` | Direct Fabric API `GET`/`PUT` because provider 1.12.1 has no workspace communication-policy resource. |
| Workspace customer-managed keys | `terraform_data` plus `set-fabric-workspace-encryption.ps1` | Public Fabric API `GET`/`POST` because provider 1.12.1 has no workspace-encryption resource. |
| Warehouse SQL schema, tables, and procedures | `terraform_data` plus `SqlClient` | TDS/SQL, not REST. The server value comes from `fabric_warehouse.properties.connection_string`. |

The default workflow does not invoke the numbered REST deployment scripts. Those scripts remain as an educational and troubleshooting alternative.

## Direct calls made by CI

[`set-capacity-state.ps1`](../scripts/powershell/set-capacity-state.ps1) targets this ARM resource:

```text
/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Fabric/capacities/{capacityName}
```

| Method | Operation | Purpose |
| --- | --- | --- |
| `GET` | Resource URI with `api-version=2023-11-01` | Read `properties.state`; an HTTP 404 is accepted only on the first full-platform deployment. |
| `POST` | `{resourceUri}/resume?api-version=2023-11-01` | Activate a paused capacity before Terraform refreshes Fabric resources. |

Resume is an operational action, not desired configuration on `azurerm_fabric_capacity`. The helper polls every five seconds for up to five minutes, and the workflow intentionally leaves the capacity active afterward. The standalone helper still supports an explicit manual suspend, but CI never invokes it.

In full-platform mode, a missing capacity is expected on the first run. The helper returns without error and Terraform creates it. In existing-workspace mode, a missing capacity remains an error. Every tfvars file must identify the capacity's Azure resource group and ARM name so the runner never skips active-state management silently.

[`set-fabric-git-credentials.ps1`](../scripts/powershell/set-fabric-git-credentials.ps1) handles Fabric's caller-specific credential contract. Before Terraform refreshes `fabric_workspace_git`, it calls:

| Method and route | Purpose |
| --- | --- |
| `GET /workspaces/{gitWorkspaceId}/git/myGitCredentials` | Check the OIDC identity's current Git credential source. |
| `PATCH /workspaces/{gitWorkspaceId}/git/myGitCredentials` | Select the configured GitHub connection for that identity when needed. |

The GitHub PAT remains inside the Fabric connection service. CI receives only the non-secret connection ID, and the operation is skipped when Git integration is disabled.

[`set-fabric-workspace-firewall.ps1`](../scripts/powershell/set-fabric-workspace-firewall.ps1) handles Fabric's workspace-level inbound policy when `fabric_workspace_firewall_ip` is set:

| Method and route | Purpose |
| --- | --- |
| `GET /workspaces/{workspaceId}/networking/communicationPolicy/inbound/firewall` | Read and preserve existing workspace IP rules. |
| `PUT /workspaces/{workspaceId}/networking/communicationPolicy/inbound/firewall` | Upsert the Azure Firewall public IP under a stable rule name. |
| `PUT /workspaces/{workspaceId}/networking/communicationPolicy` | Set `inbound.publicAccessRules.defaultAction` to `Deny`. |

Terraform creates one state-only marker per managed workspace and makes Git and item deployment depend on those markers. The operation requires workspace-admin permission and both Fabric Advanced networking tenant settings: **Configure workspace-level inbound network rules** and **Configure workspace-level IP firewall rules and trusted resource instances**. The first setting is disabled by default, and changes can take up to 15 minutes. Keep `FABRIC_MANAGE_WORKSPACE_FIREWALL=false` until a Fabric administrator enables both controls. The route and body contract are documented in [Set up workspace IP firewall rules](https://learn.microsoft.com/fabric/security/security-workspace-level-firewall-set-up#configure-workspace-ip-firewall-rules), and the tenant controls are documented in [Enable workspace inbound access protection](https://learn.microsoft.com/fabric/security/security-workspace-enable-inbound-access-protection).

[`set-fabric-workspace-encryption.ps1`](../scripts/powershell/set-fabric-workspace-encryption.ps1) manages the optional workspace CMK contract:

| Method and route | Purpose |
| --- | --- |
| `GET /workspaces/{workspaceId}/encryption` | Compare the active key and poll `Active`, `Disabled`, or `Failed` status. |
| `POST /workspaces/{workspaceId}/encryption/assign` | Assign or rotate to the configured versionless key URI. |
| `POST /workspaces/{workspaceId}/encryption/reset` | Explicitly return a managed workspace to Microsoft-managed encryption. |

The script is idempotent and honors Fabric's `Retry-After` response while a transition runs. It never resets encryption merely because a map entry was removed. The tenant CMK setting, Fabric Platform CMK service principal, Key Vault protection, and key permissions remain bootstrap prerequisites. The API supports service principals and managed identities, but the caller must hold Workspace Admin.

## Fabric API through Terraform

The Fabric provider uses `https://api.fabric.microsoft.com/v1` internally. The repository supplies resource arguments rather than constructing requests for these operations:

| Terraform resource | Managed Fabric behavior |
| --- | --- |
| `fabric_workspace` | Create/update the role-specific workspaces and assign both to the capacity. |
| `fabric_workspace_role_assignment` | Manage workspace Admin, Member, Contributor, and Viewer grants. |
| `fabric_workspace_git` | Optionally connect and initialize Git only on the authoring workspace. |
| `fabric_lakehouse` | Manage the Lakehouse. |
| `fabric_warehouse` | Manage the Warehouse and expose its SQL connection string. |
| `fabric_environment` | Manage the Spark Environment. |
| `fabric_eventhouse` | Manage the Eventhouse. |
| `fabric_kql_database` | Manage the writable KQL Database and its Eventhouse relationship. |
| `fabric_variable_library` | Manage the Variable Library. |
| `fabric_ml_experiment` | Manage the ML Experiment. |
| `fabric_notebook` | Manage the Notebook and upload its parameterized definition. |
| `fabric_data_pipeline` | Manage the Data Pipeline and upload its parameterized definition. |

This is still REST traffic at runtime, but authentication, request schema, retries, polling, drift detection, and state reconciliation belong to the provider. The provider deploys items to the CI/CD workspace and connects Git to the separate authoring workspace. Direct scripts must not manage the same workspace items in the same deployment.

## SQL data plane

[`terraform/modules/sql/deploy-procs.ps1`](../terraform/modules/sql/deploy-procs.ps1) does not call the Fabric REST API. Terraform passes the computed Warehouse server name into the script. The script then:

1. Gets an Entra token for `https://database.windows.net/` from the current Azure CLI login.
2. Opens an encrypted `System.Data.SqlClient.SqlConnection` to the Warehouse.
3. Executes the ordered files under [`fabric-git/sql`](../fabric-git/sql), splitting batches on `GO`.

Terraform has no native resource for arbitrary Fabric Warehouse T-SQL. A built-in `terraform_data` resource therefore owns this deployment hook and replaces its state-only marker when the Warehouse ID or SQL file hash changes.

## Optional direct REST scripts

The numbered PowerShell and Bash flows predate the provider-first pipeline and are still useful for learning or isolated troubleshooting. They acquire a token for `https://api.fabric.microsoft.com` and call these routes under `https://api.fabric.microsoft.com/v1`:

| Method and route | Used for |
| --- | --- |
| `GET /workspaces` | Resolve a workspace by display name. |
| `POST /workspaces` | Create a workspace. |
| `GET /capacities` | Resolve the Fabric capacity GUID from its Azure resource name. |
| `POST /workspaces/{workspaceId}/assignToCapacity` | Assign the workspace to that capacity. |
| `GET /workspaces/{workspaceId}/items` | Resolve item IDs by type and display name. |
| `POST /workspaces/{workspaceId}/lakehouses` | Create a Lakehouse. |
| `POST /workspaces/{workspaceId}/warehouses` | Create a Warehouse. |
| `POST /workspaces/{workspaceId}/environments` | Create an Environment. |
| `POST /workspaces/{workspaceId}/eventhouses` | Create an Eventhouse. |
| `POST /workspaces/{workspaceId}/kqlDatabases` | Create a writable KQL Database under the Eventhouse. |
| `POST /workspaces/{workspaceId}/variableLibraries` | Create a Variable Library. |
| `POST /workspaces/{workspaceId}/mlExperiments` | Create an ML Experiment. |
| `POST /workspaces/{workspaceId}/notebooks` | Create a Notebook with an inline Base64 definition. |
| `POST /workspaces/{workspaceId}/items` | Create a `DataPipeline` with an inline Base64 definition. |
| `POST /workspaces/{workspaceId}/items/{itemId}/updateDefinition?updateMetadata=false` | Update an existing Notebook or Pipeline definition without changing item metadata. |
| `GET /workspaces/{workspaceId}/warehouses/{warehouseId}` | Resolve the SQL endpoint in the standalone SQL script only. The Terraform path does not use this call. |
| `POST /workspaces/{workspaceId}/git/connect` | Connect Git in the optional PowerShell fallback only. |
| `POST /workspaces/{workspaceId}/git/initializeConnection` | Initialize that fallback connection with `PreferWorkspace`. |
| `DELETE /workspaces/{workspaceId}` | Delete the workspace in the explicit teardown script. |

The Git fallback connects and initializes only. It does not call status, commit-to-Git, update-from-Git, or disconnect operations.

The direct scripts perform name-based discovery from a single list response. They do not follow continuation tokens, which is another reason to prefer Terraform for shared or large workspaces.

## Long-running operations

[`common.ps1`](../scripts/powershell/common.ps1) and [`common.sh`](../scripts/bash/common.sh) handle a Fabric `202 Accepted` response as follows:

1. Read `Operation-Location`, falling back to `Location`.
2. Poll the returned operation URL until the status is `Succeeded` or `Failed`.
3. Request `{operationUrl}/result` when a result endpoint is available.
4. Time out after ten minutes in PowerShell. A `202` with no operation URL is treated as accepted, which covers capacity assignment behavior.

Terraform provider operations use the provider's own LRO implementation instead of these helpers.

## Authentication and environment isolation

- GitHub Actions uses OIDC with `azure/login`; no client secret is stored in the repository.
- The selected GitHub Environment supplies OIDC and backend controls; the matching committed tfvars supplies tenant, subscription, resource, policy, and optional adoption values.
- Terraform state is stored under an environment-specific key in the private Blob backend, and direct calls derive all IDs from that same environment configuration.
- Fabric REST fallbacks use a bearer token scoped to `https://api.fabric.microsoft.com`.
- SQL uses a separate bearer token scoped to `https://database.windows.net/`.
- Tokens are held in process memory and are not written to `.env`, Terraform variables, or output files.

## Official references

- [Complete deployment source map](DEPLOYMENT_SOURCES.md)
- [Fabric REST API](https://learn.microsoft.com/rest/api/fabric/)
- [Fabric long-running operations](https://learn.microsoft.com/rest/api/fabric/articles/long-running-operation)
- [Fabric item definitions](https://learn.microsoft.com/rest/api/fabric/articles/item-management/definitions/)
- [Fabric Git API](https://learn.microsoft.com/rest/api/fabric/core/git/)
- [Fabric workspace roles](https://learn.microsoft.com/fabric/fundamentals/roles-workspaces)
- [Customer-managed keys for Fabric workspaces](https://learn.microsoft.com/fabric/security/workspace-customer-managed-keys)
- [Fabric workspace IP firewall rules](https://learn.microsoft.com/fabric/security/security-workspace-level-firewall-set-up)
- [Workspace Monitoring overview](https://learn.microsoft.com/fabric/fundamentals/workspace-monitoring-overview)
- [Microsoft.Fabric capacities](https://learn.microsoft.com/azure/templates/microsoft.fabric/capacities)
