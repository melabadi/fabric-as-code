---
description: "Run the repository's backend-free Fabric Terraform validation and report screenshot checklist coverage for an environment."
name: "Validate Fabric Deployment"
argument-hint: "Environment name, for example dev"
agent: "Fabric Deployment Reviewer"
tools: [read, search, execute]
---
Validate the requested Fabric deployment environment, defaulting to `dev` when
no environment is supplied.

Use the `fabric-deployment-validation` skill and
[`docs/DELIVERY_SCOPE.md`](../../docs/DELIVERY_SCOPE.md). Return:

1. Terraform format, initialization, validation, and test results.
2. The environment tfvars contract result.
3. PowerShell syntax and documentation-link results.
4. A concise status table for every screenshot checklist row.
5. Any blocker that prevents deployment, clearly separated from repository validation failures.

Do not edit, deploy, commit, or push.
