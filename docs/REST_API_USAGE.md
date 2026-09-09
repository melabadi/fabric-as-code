# REST API usage

This repository is provider-first. The default GitHub Actions deployment uses Terraform for every Azure and Fabric resource supported by the installed providers. Repository code constructs HTTP requests only where the operation is not a stable declarative resource lifecycle.

## How to trace a deployment

1. Start with the [resource destination map](deployment/README.md#find-each-deployed-resource) to identify where the resource appears and its Terraform address.
2. Follow the linked root resource or module to see its inputs and dependency order.
3. Use the **Direct calls made by CI** index below only when the repository constructs an HTTP request itself.
4. Use **Fabric API through Terraform** for operations delegated to the Fabric provider, or **Optional direct REST scripts** when tracing the standalone alternative.

Provider-managed traffic and direct repository calls can reach the same Fabric
control plane, but they do not share lifecycle ownership. Use one deployment
path for a resource; do not place a Terraform-managed workspace or item under
the numbered REST scripts at the same time.

## Default workflow boundary

The Terraform owners below are conditional. Full-platform mode creates the
resource group, capacity, and workspaces. Managed-existing mode creates or
imports the workspaces on a supplied capacity. Externally managed mode consumes
workspace IDs and leaves the capacity and workspace lifecycle outside this
root.

| Concern | Deployment destination | Lifecycle owner | Protocol used by repository code |
| --- | --- | --- | --- |
| Resource group and Fabric capacity | Selected Azure subscription and resource group in full-platform mode | [`azurerm_resource_group.this`](../terraform/main.tf) and [`module.capacity`](../terraform/main.tf) when `provision_platform = true`; external otherwise | No direct create/update HTTP; AzureRM calls Azure Resource Manager. |
| CI/CD and Git authoring workspaces | Fabric tenant; assigned to the selected capacity when Terraform manages them | [`module.workspace` and `module.git_workspace`](../terraform/main.tf) in full-platform or managed-existing mode; supplied workspace IDs otherwise | No direct create/update HTTP; the Fabric provider calls the Fabric API when managed. |
| Optional Git connection | Git authoring workspace only | [`fabric_workspace_git.this`](../terraform/main.tf) | No direct connect HTTP; the Fabric provider calls the Fabric API. |
| Workspace role assignments | Selected CI/CD and/or Git workspace | [`fabric_workspace_role_assignment.this`](../terraform/main.tf) | Native Fabric provider resource; no direct HTTP. |
| Selected Fabric items and Notebook/Pipeline definitions | CI/CD deployment workspace only | [`module.items`](../terraform/main.tf): three P0 items, plus six extended items when the profile is `all` | The Fabric provider calls the Fabric API and handles long-running operations. |
| Capacity activation before deployment | Azure capacity ARM resource ID | [`set-capacity-state.ps1`](../scripts/powershell/set-capacity-state.ps1) | Direct Azure Resource Manager `GET`/`POST` reads and resumes the capacity. |
| Caller-specific Git credentials | Git authoring workspace, scoped to the OIDC identity | [`terraform_data.git_credentials`](../terraform/main.tf) plus [`set-fabric-git-credentials.ps1`](../scripts/powershell/set-fabric-git-credentials.ps1) | Direct Fabric API `GET`/`PATCH` before provider reconciliation. |
| Workspace inbound IP allowlist | Each targeted managed workspace | [`terraform_data.workspace_firewall`](../terraform/main.tf) plus [`set-fabric-workspace-firewall.ps1`](../scripts/powershell/set-fabric-workspace-firewall.ps1) | Direct Fabric API `GET`/`PUT`; provider 1.12.1 has no communication-policy resource. |
| Workspace customer-managed keys | Each workspace named in `workspace_encryption` | [`terraform_data.workspace_encryption`](../terraform/main.tf) plus [`set-fabric-workspace-encryption.ps1`](../scripts/powershell/set-fabric-workspace-encryption.ps1) | Direct Fabric API `GET`/`POST`; provider 1.12.1 has no workspace-encryption resource. |
| Warehouse SQL schema, tables, and procedures | Inside the CI/CD workspace Warehouse | [`module.sql`](../terraform/main.tf) plus [`deploy-procs.ps1`](../terraform/modules/sql/deploy-procs.ps1) | TDS/SQL, not REST. The server comes from `fabric_warehouse.properties.connection_string`. |

The default workflow does not invoke the numbered REST deployment scripts. Those scripts remain as an educational and troubleshooting alternative.

## Direct calls made by CI

| Call site | Target | Methods and routes | Why it is direct |
| --- | --- | --- | --- |
| [`deploy-terraform.ps1`](../scripts/powershell/deploy-terraform.ps1) | Fabric tenant | `GET https://api.fabric.microsoft.com/v1/workspaces` | Authentication and egress preflight only; it does not manage a workspace. |
| [`set-capacity-state.ps1`](../scripts/powershell/set-capacity-state.ps1) | Azure capacity ARM resource | `GET {resourceId}` and `POST {resourceId}/resume` | Resume is an operational action, not capacity desired state. |
| [`set-fabric-git-credentials.ps1`](../scripts/powershell/set-fabric-git-credentials.ps1) | Git authoring workspace and current caller | `GET`/`PATCH /workspaces/{id}/git/myGitCredentials` | Fabric Git credentials are caller-specific. |
| [`set-fabric-workspace-firewall.ps1`](../scripts/powershell/set-fabric-workspace-firewall.ps1) | Each targeted workspace | `GET`/`PUT /workspaces/{id}/networking/communicationPolicy/inbound/firewall`; `PUT /workspaces/{id}/networking/communicationPolicy` | The installed Fabric provider has no workspace communication-policy resource. |
| [`set-fabric-workspace-encryption.ps1`](../scripts/powershell/set-fabric-workspace-encryption.ps1) | Each workspace in the encryption map | `GET /workspaces/{id}/encryption`; `POST /workspaces/{id}/encryption/assign` or `/reset` | The installed Fabric provider has no workspace-encryption resource. |

[`verify-fabric-network.ps1`](../scripts/powershell/verify-fabric-network.ps1)
also reads Fabric workspace, item, firewall, encryption, and Warehouse metadata
after deployment. Those requests are verification canaries, not lifecycle
owners.

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

The numbered PowerShell and Bash flows predate the provider-first pipeline and are still useful for learning or isolated troubleshooting. They acquire a token for `https://api.fabric.microsoft.com` and call these routes under `https://api.fabric.microsoft.com/v1`. Bash counterparts exist under [`scripts/bash/`](../scripts/bash) for steps 03 through 06 and 99; the step 07 Git fallback is PowerShell-only. Step 05 always deploys all nine demonstration items and has no `p0` profile switch.

| Method and route | Used for | PowerShell source |
| --- | --- | --- |
| `GET /workspaces` | Resolve a workspace by display name. | [`common.ps1`](../scripts/powershell/common.ps1) |
| `POST /workspaces` | Create a workspace. | [`03-create-workspace.ps1`](../scripts/powershell/03-create-workspace.ps1) |
| `GET /capacities` | Resolve the Fabric capacity GUID from its Azure resource name. | [`common.ps1`](../scripts/powershell/common.ps1) |
| `POST /workspaces/{workspaceId}/assignToCapacity` | Assign the workspace to that capacity. | [`04-assign-capacity.ps1`](../scripts/powershell/04-assign-capacity.ps1) |
| `GET /workspaces/{workspaceId}/items` | Resolve item IDs by type and display name. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/lakehouses` | Create a Lakehouse. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/warehouses` | Create a Warehouse. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/environments` | Create an Environment. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/eventhouses` | Create an Eventhouse. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/kqlDatabases` | Create a writable KQL Database under the Eventhouse. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/variableLibraries` | Create a Variable Library. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/mlExperiments` | Create an ML Experiment. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/notebooks` | Create a Notebook with an inline Base64 definition. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/items` | Create a `DataPipeline` with an inline Base64 definition. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `POST /workspaces/{workspaceId}/items/{itemId}/updateDefinition?updateMetadata=false` | Update an existing Notebook or Pipeline definition without changing item metadata. | [`05-deploy-items.ps1`](../scripts/powershell/05-deploy-items.ps1) |
| `GET /workspaces/{workspaceId}/warehouses/{warehouseId}` | Resolve the SQL endpoint in the standalone SQL script only. The Terraform path does not use this call. | [`06-deploy-stored-procedures.ps1`](../scripts/powershell/06-deploy-stored-procedures.ps1) |
| `POST /workspaces/{workspaceId}/git/connect` | Connect Git in the optional PowerShell fallback only. | [`07-git-integration.ps1`](../scripts/powershell/07-git-integration.ps1) |
| `POST /workspaces/{workspaceId}/git/initializeConnection` | Initialize that fallback connection with `PreferWorkspace`. | [`07-git-integration.ps1`](../scripts/powershell/07-git-integration.ps1) |
| `DELETE /workspaces/{workspaceId}` | Delete the workspace in the explicit teardown script. | [`99-teardown.ps1`](../scripts/powershell/99-teardown.ps1) |

The Git fallback connects and initializes the same single workspace recorded in
`.state.json`; it is not equivalent to Terraform's dedicated authoring
workspace. It does not call status, commit-to-Git, update-from-Git, or
disconnect operations.

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
