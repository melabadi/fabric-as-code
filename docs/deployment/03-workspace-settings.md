# 3. Workspace settings

The root module applies workspace access and security policy after workspace IDs
are known and before Git or item deployment begins.

## Code map

| Setting | Terraform and implementation |
| --- | --- |
| Workspace roles | [`fabric_workspace_role_assignment.this`](../../terraform/main.tf), configured by [`workspace_role_assignments`](../../terraform/variables.tf) |
| Customer-managed keys | [`terraform_data.workspace_encryption`](../../terraform/main.tf) calls [`set-fabric-workspace-encryption.ps1`](../../scripts/powershell/set-fabric-workspace-encryption.ps1) |
| Inbound IP policy | [`terraform_data.workspace_firewall`](../../terraform/main.tf) calls [`set-fabric-workspace-firewall.ps1`](../../scripts/powershell/set-fabric-workspace-firewall.ps1) |
| Monitoring contract | [`workspace_security_summary`](../../terraform/outputs.tf) feeds [deployment](../../.github/workflows/deploy-fabric.yml) and [scheduled](../../.github/workflows/verify-fabric-network.yml) checks |
| Live environment values | [`terraform/environments/`](../../terraform/environments) |

## Dependency order

1. Terraform expands each role declaration across its selected `cicd`, `git`,
   or both workspace targets.
2. The inbound policy marker preserves existing named rules, adds the deployment
   egress address, and changes the public default action to `Deny` when enabled.
3. The encryption marker assigns, rotates, or explicitly resets the configured
   versionless Key Vault key and waits for a terminal Fabric status.
4. Git and item resources depend on the applicable policy markers so they don't
   start before workspace access is ready.
5. Terraform outputs drive post-apply and six-hour reachability, CMK, firewall,
   and Warehouse TDS canaries.

## Provider boundary

Workspace roles use the native Fabric provider resource. The installed provider
doesn't expose workspace encryption or communication-policy resources, so those
two settings use `terraform_data` state markers plus public Fabric REST APIs.
Removing an encryption map entry leaves the current setting unmanaged; setting
`enabled = false` explicitly resets it to Microsoft-managed encryption.

Fabric Workspace monitoring is a separate portal lifecycle. Terraform reports
it as `manual-portal` and doesn't call a private endpoint.

## Prerequisites and eligibility

- CMK requires the tenant setting, the Fabric Platform CMK service principal,
  an RSA versionless key, soft delete, purge protection, and key permissions.
- CI/CD workspace CMK requires `item_deployment_profile = "p0"`; unsupported
  item types prevent Fabric from enabling workspace encryption.
- Inbound restriction requires both Fabric Advanced networking tenant controls
  and a workspace whose items are eligible for inbound restriction.
- The deployment identity must be Workspace Admin for CMK and network policy.

## Verify

```powershell
terraform -chdir=terraform output -json workspace_security_summary
pwsh ./scripts/powershell/verify-fabric-network.ps1
```

The verification script checks private state DNS, Azure service tags, firewall
rules, Fabric REST, optional workspace CMK and inbound policy, and Warehouse TDS.

## Learn more

- [Fabric provider `fabric_workspace_role_assignment` resource](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/workspace_role_assignment)
- [Terraform `terraform_data` resource](https://developer.hashicorp.com/terraform/language/resources/terraform-data)
- [Fabric workspace roles](https://learn.microsoft.com/fabric/fundamentals/roles-workspaces)
- [Customer-managed keys for Fabric workspaces](https://learn.microsoft.com/fabric/security/workspace-customer-managed-keys)
- [Set up workspace IP firewall rules](https://learn.microsoft.com/fabric/security/security-workspace-level-firewall-set-up)
- [Enable workspace inbound access protection](https://learn.microsoft.com/fabric/security/security-workspace-enable-inbound-access-protection)
- [Fabric Workspace monitoring](https://learn.microsoft.com/fabric/fundamentals/workspace-monitoring-overview)
