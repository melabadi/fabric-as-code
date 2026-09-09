# 5. Fabric files and item deployment

[`fabric-git/`](../../fabric-git) is the canonical content root for both the Git
authoring workspace and Terraform deployment to the CI/CD workspace. Terraform
doesn't create a second rendered source tree.

## Code map

| Responsibility | Implementation |
| --- | --- |
| Canonical Fabric Git definitions | [`fabric-git/`](../../fabric-git) |
| Create items and upload definitions | [`terraform/modules/items/main.tf`](../../terraform/modules/items/main.tf) |
| Configure item names and source root | [`terraform/modules/items/variables.tf`](../../terraform/modules/items/variables.tf) |
| Publish item IDs and Warehouse endpoint | [`terraform/modules/items/outputs.tf`](../../terraform/modules/items/outputs.tf) |
| Deploy Warehouse SQL objects | [`terraform/modules/sql/`](../../terraform/modules/sql) and [`fabric-git/sql/`](../../fabric-git/sql) |
| Adopt existing item IDs | [`terraform/imports.tf`](../../terraform/imports.tf) |

## Source-to-resource map

| Source | Terraform resource | Deployment behavior |
| --- | --- | --- |
| `lh_git_authoring_demo.Lakehouse/` | `fabric_lakehouse` | Uploads Lakehouse metadata and shortcut definitions. |
| `nb_git_authoring_demo.Notebook/notebook-content.py` | `fabric_notebook` | Uploads the native notebook definition. |
| `pl_git_authoring_demo.DataPipeline/pipeline-content.json` | `fabric_data_pipeline` | Replaces the source Notebook logical ID and neutral workspace ID in memory. |
| Environment name | `fabric_environment` | Creates the Fabric item in the `all` profile. |
| Eventhouse and KQL names | `fabric_eventhouse`, `fabric_kql_database` | Creates the Eventhouse before its writable child database. |
| Variable Library name | `fabric_variable_library` | Creates the item in the `all` profile. |
| ML Experiment name | `fabric_ml_experiment` | Creates the item in the `all` profile. |
| `sql/*.sql` | `terraform_data.stored_procs` | Executes ordered T-SQL batches against the Warehouse with an Entra token. |

## Deployment flow

1. Terraform reads the native definitions directly from `fabric-git/`.
2. `.platform` remains Git metadata. Terraform reads the Notebook logical ID
   from it but doesn't upload `.platform` as an item definition part.
3. The Lakehouse is available before the Notebook; the Notebook physical ID is
   available before the Pipeline definition is rendered.
4. `TextReplace` parameters translate logical and neutral IDs in memory. No
   generated files are written back to the repository.
5. `prevent_destroy` protects every selected Fabric item.
6. After the Warehouse exists, the SQL module hashes and executes the ordered
   files under `fabric-git/sql/` over encrypted TDS.

Use `item_deployment_profile = "p0"` for Lakehouse, Warehouse, and Notebook.
Use `all` to add Environment, Eventhouse, KQL Database, Variable Library,
ML Experiment, and Data Pipeline.

## Verify

```powershell
terraform -chdir=terraform output -json
terraform -chdir=terraform test -no-color
```

Compare the output IDs with the CI/CD workspace. For the Warehouse, run an
authenticated query against the configured database or use the repository's
post-deployment canary.

## Learn more

- [Fabric provider resources](https://registry.terraform.io/providers/microsoft/fabric/latest/docs)
- [Fabric provider `fabric_lakehouse`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/lakehouse)
- [Fabric provider `fabric_warehouse`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/warehouse)
- [Fabric provider `fabric_notebook`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/notebook)
- [Fabric provider `fabric_data_pipeline`](https://registry.terraform.io/providers/microsoft/fabric/latest/docs/resources/data_pipeline)
- [Fabric item definitions](https://learn.microsoft.com/rest/api/fabric/articles/item-management/definitions/)
- [Fabric Git source-code format](https://learn.microsoft.com/fabric/cicd/git-integration/source-code-format)
- [Fabric Warehouse connectivity](https://learn.microsoft.com/fabric/data-warehouse/connectivity)
- [Terraform `terraform_data` resource](https://developer.hashicorp.com/terraform/language/resources/terraform-data)