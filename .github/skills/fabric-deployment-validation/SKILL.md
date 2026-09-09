---
name: fabric-deployment-validation
description: "Validate the Fabric Terraform deployment, screenshot delivery scope, environment tfvars, PowerShell syntax, and documentation links. Use before a PR, push, or deployment readiness review."
argument-hint: "Environment name, default dev"
user-invocable: true
disable-model-invocation: false
---
# Fabric Deployment Validation

## Procedure

1. Read [`docs/DELIVERY_SCOPE.md`](../../../docs/DELIVERY_SCOPE.md) and identify the requested environment under `terraform/environments/`.
2. Confirm the working tree and preserve unrelated changes.
3. Run Terraform checks in a temporary `TF_DATA_DIR` so a prior private-backend initialization can't leak into validation:

   ```powershell
   terraform -chdir=terraform fmt -check -recursive
   $env:TF_DATA_DIR = Join-Path $env:TEMP 'fabric-validation'
   Remove-Item $env:TF_DATA_DIR -Recurse -Force -ErrorAction SilentlyContinue
   terraform -chdir=terraform init -backend=false -input=false
   terraform -chdir=terraform validate -no-color
   terraform -chdir=terraform test -no-color
   ```

4. Validate the selected tfvars contract:

   ```powershell
   pwsh ./scripts/powershell/validate-terraform-var-file.ps1 `
     -VarFile ./terraform/environments/dev.tfvars `
     -ExpectedEnvironment dev
   ```

5. Run `pwsh ./scripts/powershell/test-terraform-environment-selection.ps1`.
6. Run `pwsh ./scripts/powershell/test-public-repository-hygiene.ps1`.
7. Parse every `scripts/powershell/*.ps1` file with the PowerShell parser without executing it.
8. Resolve local Markdown links in changed documentation and verify new provider links use official Terraform Registry URLs.
9. Run `git diff --check` and review staged scope before any commit or push.
10. Report each screenshot row as `Delivered`, `External prerequisite`, `Optional extended`, or `Outside P0`.

## Deployment Gate

Do not run apply merely because validation passes. Deployment requires the
private backend network path, the matching GitHub Environment/OIDC identity,
and any tenant-admin prerequisites documented in the delivery scope.
