# Fabric-as-Code Project Instructions

## Start Here

- Use [`docs/DELIVERY_SCOPE.md`](../docs/DELIVERY_SCOPE.md) as the acceptance contract.
- Use [`docs/deployment/README.md`](../docs/deployment/README.md) for the ordered deployment flow.
- Use [`docs/DEPLOYMENT_SOURCES.md`](../docs/DEPLOYMENT_SOURCES.md) for official provider and Microsoft documentation.

## Ownership

- Terraform manages the CI/CD workspace items; Fabric Git synchronizes only the authoring workspace.
- `fabric-git/` is the canonical source for Fabric-native definitions and Warehouse SQL.
- Preserve the distinction between `p0` and `all`; don't claim white/out-of-scope items as delivered.
- Repository creation, tenant settings, the Fabric Platform CMK enterprise application, and portal-only Workspace monitoring are administrator handoffs.

## Safety

- Never enable workspace CMK unless its tenant, key, permission, and supported-item prerequisites are satisfied.
- Never enable workspace inbound deny policy until Fabric reports the workspace eligible and the deployment egress IP is reachable.
- Never bypass private Terraform state policy without explicit approval and immediate rollback.
- Preserve unrelated worktree changes.

## Validation

- Run Terraform formatting, backend-free initialization, validation, and mocked tests before proposing a push.
- Validate every changed environment tfvars file with `scripts/powershell/validate-terraform-var-file.ps1`.
- Treat PRs as unprivileged validation; deployment occurs after merge to `main` through the matching GitHub Environment.
