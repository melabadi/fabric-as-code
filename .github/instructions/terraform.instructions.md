---
description: "Use when editing Terraform, tfvars, Fabric resources, workspace settings, imports, outputs, or deployment tests in this repository."
name: "Fabric Terraform Instructions"
applyTo: "terraform/**/*.tf, terraform/**/*.tftest.hcl, terraform/**/*.tfvars"
---
# Fabric Terraform Guidelines

- Follow the stage ownership in [`docs/deployment/README.md`](../../docs/deployment/README.md).
- Prefer native `hashicorp/azurerm` and `microsoft/fabric` resources. Keep the existing `terraform_data` bridges only where the installed provider has no lifecycle resource.
- Keep `fabric-git/` as the sole content source; render target IDs in memory without generated repository copies.
- Preserve `prevent_destroy`, import addresses, moved blocks, and the guarded delete policy.
- Keep CI/CD and Git authoring workspace IDs separate.
- Keep CMK validation aligned with Fabric's supported item list and the `p0` profile.
- Add a nearby official Terraform Registry `Learn more` link when introducing a provider resource.

For clean backend-free validation on a machine that previously initialized the private backend, use an isolated `TF_DATA_DIR`:

```powershell
$env:TF_DATA_DIR = Join-Path $env:TEMP 'fabric-terraform-validation'
Remove-Item $env:TF_DATA_DIR -Recurse -Force -ErrorAction SilentlyContinue
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
terraform -chdir=terraform test -no-color
```
