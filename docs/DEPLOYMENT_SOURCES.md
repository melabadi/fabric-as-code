# Deployment sources

This catalog maps each deployed component to its repository implementation and
authoritative product documentation. Provider documentation defines the
Terraform schema; Microsoft and GitHub documentation defines service behavior,
prerequisites, and limitations. The links were verified on 2026-09-05.

For the ordered operator journey, start with the
[end-to-end Terraform deployment guide](deployment/README.md). Each stage page
links back to the exact resources and scripts cataloged here.

For agent-assisted repository validation, see
[GitHub Copilot tooling](GHCP_TOOLING.md).

## Reference status

| Control | Deployment status |
| --- | --- |
| Workspace role assignments | Implemented with native Fabric provider resources. Populate principal object IDs in a customer-owned environment file. |
| Customer-managed key | Assignment, rotation, reset, and polling are implemented. Enable only after the tenant, key, permission, and supported-item prerequisites are satisfied. |
| Workspace inbound policy | IP rule preservation and default-deny automation are implemented. Enable only after both tenant controls and workspace eligibility are confirmed. |
| Role-aware deployment monitoring | Azure Firewall diagnostics and post-apply/scheduled Fabric and Warehouse canaries are implemented. Customers supply the runner, backend, and monitored environment values. |
| Fabric Workspace monitoring | Manual portal handoff. It is deliberately not represented as a Terraform-managed resource. |

The public environment files are non-deployable templates. This repository does
not publish customer tenant, subscription, workspace, principal, connection,
state, or resource identifiers.

## Execution, identity, and state

| Deployment part | Repository implementation | Authoritative documentation |
| --- | --- | --- |
| Terraform style and lifecycle | [`terraform/`](../terraform) | [Terraform style guide](https://developer.hashicorp.com/terraform/language/style), [Terraform dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock) |
| GitHub Actions deployment and OIDC | [`.github/workflows/deploy-fabric.yml`](../.github/workflows/deploy-fabric.yml) | [Deploy to Azure with OpenID Connect](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect), [GitHub environments](https://docs.github.com/actions/deployment/targeting-different-environments/managing-environments-for-deployment) |
| Azure Blob state, locking, and Entra authentication | [`terraform/providers.tf`](../terraform/providers.tf), [`scripts/powershell/deploy-terraform.ps1`](../scripts/powershell/deploy-terraform.ps1) | [Terraform `azurerm` backend](https://developer.hashicorp.com/terraform/language/backend/azurerm), [Azure Blob versioning](https://learn.microsoft.com/azure/storage/blobs/versioning-overview), [Blob soft delete](https://learn.microsoft.com/azure/storage/blobs/soft-delete-blob-overview) |
| GitHub-hosted larger runner VNet injection | [`terraform/runner-network/`](../terraform/runner-network) | [About Azure VNet private networking](https://docs.github.com/organizations/managing-organization-settings/about-azure-private-networking-for-github-hosted-runners-in-your-organization), [Configure Azure VNet private networking](https://docs.github.com/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization) |
| Environment-specific state and deployment selection | [`scripts/powershell/select-terraform-environments.ps1`](../scripts/powershell/select-terraform-environments.ps1), [`terraform/environments/`](../terraform/environments) | [Terraform partial backend configuration](https://developer.hashicorp.com/terraform/language/backend#partial-configuration), [GitHub workflow events](https://docs.github.com/actions/using-workflows/events-that-trigger-workflows) |

GitHub documents Azure VNet injection as an organization-level feature backed
by a larger-runner group. A repository owned by a personal account cannot attach
the `GitHub.Network/networkSettings` resource to a hosted runner. Move the
repository to an organization, create its network configuration and runner
group, grant the repository access, and only then select that runner label.

## Azure platform and network

| Deployment part | Repository implementation | Authoritative documentation |
| --- | --- | --- |
| Resource group and Fabric capacity | [`terraform/main.tf`](../terraform/main.tf), [`terraform/modules/capacity/`](../terraform/modules/capacity), [`infra/capacity.bicep`](../infra/capacity.bicep) | [`Microsoft.Fabric/capacities`](https://learn.microsoft.com/azure/templates/microsoft.fabric/capacities), [`azurerm_fabric_capacity`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/fabric_capacity) |
| Virtual network, delegated runner subnet, and deny-inbound NSG | [`terraform/runner-network/main.tf`](../terraform/runner-network/main.tf) | [GitHub runner network communication](https://docs.github.com/organizations/managing-organization-settings/about-azure-private-networking-for-github-hosted-runners-in-your-organization#about-network-communication), [Azure NSG overview](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview) |
| Azure Firewall, stable egress, DNS proxy, and threat intelligence | [`terraform/runner-network/main.tf`](../terraform/runner-network/main.tf) | [Azure Firewall overview](https://learn.microsoft.com/azure/firewall/overview), [Azure Firewall DNS settings](https://learn.microsoft.com/azure/firewall/dns-settings), [Azure Firewall threat intelligence](https://learn.microsoft.com/azure/firewall/threat-intel) |
| Fabric and Warehouse egress rules | [`terraform/runner-network/main.tf`](../terraform/runner-network/main.tf), [`scripts/powershell/verify-fabric-network.ps1`](../scripts/powershell/verify-fabric-network.ps1) | [Fabric service tags](https://learn.microsoft.com/fabric/security/security-service-tags), [Warehouse connectivity](https://learn.microsoft.com/fabric/data-warehouse/connectivity), [Fabric URL allowlist](https://learn.microsoft.com/fabric/security/fabric-allow-list-urls) |
| Private state endpoint and DNS | [`terraform/runner-network/main.tf`](../terraform/runner-network/main.tf) | [Private endpoints for Azure Storage](https://learn.microsoft.com/azure/storage/common/storage-private-endpoints), [Azure Private DNS](https://learn.microsoft.com/azure/dns/private-dns-overview) |
| Least-privilege state and network-reader roles | [`terraform/runner-network/main.tf`](../terraform/runner-network/main.tf) | [Azure RBAC overview](https://learn.microsoft.com/azure/role-based-access-control/overview), [`Storage Blob Data Contributor`](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-contributor) |
| Firewall logs, metrics, and Log Analytics | [`terraform/runner-network/main.tf`](../terraform/runner-network/main.tf) | [Azure Monitor diagnostic settings](https://learn.microsoft.com/azure/azure-monitor/platform/diagnostic-settings), [Azure Firewall monitoring reference](https://learn.microsoft.com/azure/firewall/monitor-firewall-reference), [Log Analytics workspace overview](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview) |

## Fabric workspace governance

| Deployment part | Repository implementation | Authoritative documentation |
| --- | --- | --- |
| CI/CD and Git authoring workspaces | [`terraform/modules/workspace/`](../terraform/modules/workspace), [`terraform/main.tf`](../terraform/main.tf) | [`fabric_workspace`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace), [Create a workspace](https://learn.microsoft.com/fabric/fundamentals/create-workspaces) |
| Workspace role assignments | [`fabric_workspace_role_assignment.this`](../terraform/main.tf), [`workspace_role_assignments`](../terraform/variables.tf) | [`fabric_workspace_role_assignment`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace_role_assignment), [Fabric workspace roles](https://learn.microsoft.com/fabric/fundamentals/roles-workspaces) |
| Workspace customer-managed key assignment, rotation, reset, and status | [`terraform_data.workspace_encryption`](../terraform/main.tf), [`set-fabric-workspace-encryption.ps1`](../scripts/powershell/set-fabric-workspace-encryption.ps1) | [Customer-managed keys for Fabric workspaces](https://learn.microsoft.com/fabric/security/workspace-customer-managed-keys), [Key Vault Crypto Service Encryption User](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/security#key-vault-crypto-service-encryption-user) |
| Workspace inbound deny policy and IP allowlist | [`terraform_data.workspace_firewall`](../terraform/main.tf), [`set-fabric-workspace-firewall.ps1`](../scripts/powershell/set-fabric-workspace-firewall.ps1) | [Set up workspace IP firewall rules](https://learn.microsoft.com/fabric/security/security-workspace-level-firewall-set-up), [Enable workspace inbound access protection](https://learn.microsoft.com/fabric/security/security-workspace-enable-inbound-access-protection) |
| Git connection and caller credentials | [`fabric_workspace_git.this`](../terraform/main.tf), [`set-fabric-git-credentials.ps1`](../scripts/powershell/set-fabric-git-credentials.ps1) | [`fabric_workspace_git`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace_git), [Fabric Git integration](https://learn.microsoft.com/fabric/cicd/git-integration/intro-to-git-integration), [Fabric Git REST API](https://learn.microsoft.com/rest/api/fabric/core/git) |

CMK bootstrap is intentionally separate from workspace deployment because it
requires tenant-level duties. A Cloud Application Administrator must create the
**Fabric Platform CMK** service principal with application ID
`61d6811f-7544-4e75-a1e6-1c59c0383311`, and a Fabric administrator must enable
**Apply customer-managed keys**. The key must be RSA, versionless, and protected
by soft delete and purge protection. Run
[`bootstrap-fabric-security.ps1`](../scripts/powershell/bootstrap-fabric-security.ps1)
under those privileges before adding the key URI to `workspace_encryption`.

The `all` item profile contains KQL Database and Variable Library, which aren't
on Fabric's current CMK-supported item list. The root validation therefore
allows CI/CD workspace CMK only with `item_deployment_profile = "p0"`.

## Fabric items and data plane

| Deployment part | Repository implementation | Authoritative documentation |
| --- | --- | --- |
| Lakehouse | [`fabric_lakehouse.this`](../terraform/modules/items/main.tf) | [`fabric_lakehouse`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/lakehouse), [Lakehouse REST API](https://learn.microsoft.com/rest/api/fabric/lakehouse/items) |
| Warehouse | [`fabric_warehouse.this`](../terraform/modules/items/main.tf) | [`fabric_warehouse`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/warehouse), [Warehouse REST API](https://learn.microsoft.com/rest/api/fabric/warehouse/items) |
| Notebook | [`fabric_notebook.this`](../terraform/modules/items/main.tf) | [`fabric_notebook`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/notebook), [Notebook REST API](https://learn.microsoft.com/rest/api/fabric/notebook/items) |
| Spark Environment | [`fabric_environment.this`](../terraform/modules/items/main.tf) | [`fabric_environment`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/environment), [Environment REST API](https://learn.microsoft.com/rest/api/fabric/environment/items) |
| Eventhouse and writable KQL Database | [`fabric_eventhouse.this`](../terraform/modules/items/main.tf), [`fabric_kql_database.this`](../terraform/modules/items/main.tf) | [`fabric_eventhouse`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/eventhouse), [`fabric_kql_database`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/kql_database), [Eventhouse REST API](https://learn.microsoft.com/rest/api/fabric/eventhouse/items), [KQL Database REST API](https://learn.microsoft.com/rest/api/fabric/kqldatabase/items) |
| Variable Library | [`fabric_variable_library.this`](../terraform/modules/items/main.tf) | [`fabric_variable_library`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/variable_library), [Variable Library REST API](https://learn.microsoft.com/rest/api/fabric/variablelibrary/items) |
| ML Experiment | [`fabric_ml_experiment.this`](../terraform/modules/items/main.tf) | [`fabric_ml_experiment`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/ml_experiment), [ML Experiment REST API](https://learn.microsoft.com/rest/api/fabric/mlexperiment/items) |
| Data Pipeline | [`fabric_data_pipeline.this`](../terraform/modules/items/main.tf) | [`fabric_data_pipeline`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/data_pipeline), [Data Pipeline REST API](https://learn.microsoft.com/rest/api/fabric/datapipeline/items) |
| Git-native definitions and ID substitution | [`fabric-git/`](../fabric-git), [`terraform/modules/items/main.tf`](../terraform/modules/items/main.tf) | [Fabric item definitions](https://learn.microsoft.com/rest/api/fabric/articles/item-management/definitions/), [Fabric Git source-code format](https://learn.microsoft.com/fabric/cicd/git-integration/source-code-format) |
| Warehouse schema, tables, and stored procedures | [`fabric-git/sql/`](../fabric-git/sql), [`terraform/modules/sql/`](../terraform/modules/sql) | [Warehouse connectivity](https://learn.microsoft.com/fabric/data-warehouse/connectivity), [Microsoft Entra authentication for Fabric Warehouse](https://learn.microsoft.com/fabric/data-warehouse/entra-id-authentication), [T-SQL surface area](https://learn.microsoft.com/fabric/data-warehouse/tsql-surface-area) |

## Verification and monitoring

| Deployment part | Repository implementation | Authoritative documentation |
| --- | --- | --- |
| Terraform formatting, validation, tests, guarded plan/apply, and convergence | [`deploy-terraform.ps1`](../scripts/powershell/deploy-terraform.ps1), [`terraform/tests/`](../terraform/tests) | [`terraform validate`](https://developer.hashicorp.com/terraform/cli/commands/validate), [`terraform test`](https://developer.hashicorp.com/terraform/cli/commands/test), [Saved plan apply](https://developer.hashicorp.com/terraform/cli/commands/apply#saved-plan-mode) |
| Post-deployment and six-hour canaries | [`.github/workflows/verify-fabric-network.yml`](../.github/workflows/verify-fabric-network.yml), [`verify-fabric-network.ps1`](../scripts/powershell/verify-fabric-network.ps1) | [Scheduled workflows](https://docs.github.com/actions/using-workflows/events-that-trigger-workflows#schedule), [Fabric REST API](https://learn.microsoft.com/rest/api/fabric/) |
| Fabric Workspace monitoring | Manual workspace-admin handoff | [Workspace Monitoring overview](https://learn.microsoft.com/fabric/fundamentals/workspace-monitoring-overview), [Enable Workspace monitoring](https://learn.microsoft.com/fabric/fundamentals/enable-workspace-monitoring) |
| Fabric API long-running operations | [`scripts/powershell/common.ps1`](../scripts/powershell/common.ps1), [`scripts/bash/common.sh`](../scripts/bash/common.sh) | [Fabric long-running operations](https://learn.microsoft.com/rest/api/fabric/articles/long-running-operation) |

Fabric Workspace monitoring is distinct from this repository's deployment
canaries and Azure Firewall diagnostics. Microsoft's current setup article
documents a workspace-admin portal flow that creates a monitoring Eventhouse;
the installed Fabric provider and public REST surface don't expose that
lifecycle. The Terraform output reports `manual-portal` so automation doesn't
claim to manage it.
