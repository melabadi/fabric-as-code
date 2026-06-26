# Fabric-as-Code — Terraform

A Terraform implementation of the same end-to-end deployment as the scripts in
[`../scripts`](../scripts), for teams that prefer declarative IaC with state.

It uses two providers:

- **`hashicorp/azurerm`** → the Fabric **capacity** (`azurerm_fabric_capacity`)
- **`microsoft/fabric`** → the **workspace** and **items** (`fabric_workspace`,
  `fabric_lakehouse`, `fabric_warehouse`, `fabric_notebook`,
  `fabric_data_pipeline`)

Stored procedures are deployed by a small `null_resource` provisioner
([`modules/sql/deploy-procs.ps1`](modules/sql/deploy-procs.ps1)) — Terraform has
no native T-SQL, so this reuses the .NET `SqlClient` + Entra-token approach.

## What maps to what

| Script step | Terraform |
| --- | --- |
| `02` capacity (Bicep) | `module.capacity` → `azurerm_fabric_capacity` + `data.fabric_capacity` (GUID) |
| `03` create workspace | `module.workspace` → `fabric_workspace` |
| `04` assign capacity | `capacity_id` on `fabric_workspace` |
| `05` deploy items | `module.items` → lakehouse / warehouse / notebook / data pipeline |
| `06` stored procedures | `module.sql` → `null_resource` + `deploy-procs.ps1` |
| `.state.json` | Terraform state |

The notebook and pipeline **reuse the same definition files** as the scripts
([`../fabric-items`](../fabric-items)); the `__TOKENS__` are substituted with real
GUIDs and rendered to `.rendered/` before upload — single source of truth.

## Prerequisites

- Terraform >= 1.5, Azure CLI (`az login` done), PowerShell 7+ (`pwsh`)
- Fabric enabled in the tenant; the identity must be a **capacity admin**
- Provider versions resolve from the public registry on `terraform init`

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform plan
terraform apply
```

Tear down:

```bash
terraform destroy
```

## Auth

Both providers reuse your **Azure CLI** session by default. For CI/CD, use a
service principal via the standard environment variables
(`ARM_CLIENT_ID` / `ARM_CLIENT_SECRET` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID`,
and the `FABRIC_*` equivalents) and a remote state backend.

## Notes & caveats

- **Provider coverage**: the `microsoft/fabric` provider covers the items used
  here; newer item types occasionally lag the REST API — fill gaps with a
  `null_resource` + `az`/REST if needed.
- **Stored procedures** remain imperative (a provisioner), by design.
- This folder is an **alternative** to the scripts, not a replacement — pick
  whichever your team standardises on. Both produce the same environment.
