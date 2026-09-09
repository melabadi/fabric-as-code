# GitHub Copilot tooling

This repository includes workspace-scoped GitHub Copilot customizations for
understanding and validating the Fabric deployment. No credentials are stored
in these files.

## Included tooling

| Tool | Purpose | Location |
| --- | --- | --- |
| Project instructions | Always-on architecture, ownership, safety, and validation rules | [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) |
| Terraform instructions | Applied when Terraform and tfvars files are edited | [`.github/instructions/terraform.instructions.md`](../.github/instructions/terraform.instructions.md) |
| Deployment reviewer | Read-only custom agent for scope and readiness reviews | [`.github/agents/fabric-deployment-reviewer.agent.md`](../.github/agents/fabric-deployment-reviewer.agent.md) |
| Validation skill | Repeatable backend-free validation procedure | [`.github/skills/fabric-deployment-validation/SKILL.md`](../.github/skills/fabric-deployment-validation/SKILL.md) |
| Validation prompt | Slash prompt that invokes the reviewer for one environment | [`.github/prompts/validate-fabric-deployment.prompt.md`](../.github/prompts/validate-fabric-deployment.prompt.md) |
| MCP servers | Azure resource/Terraform tools and GitHub repository tools | [`.vscode/mcp.json`](../.vscode/mcp.json) |

## Use

1. Open the repository in VS Code with GitHub Copilot Chat enabled.
2. Open **Chat: Open Customizations** to inspect the shared instructions,
   prompt, skill, and agent.
3. Select **Fabric Deployment Reviewer** for a read-only readiness audit, or run
   `/validate-fabric-deployment` and provide an environment name.
4. Open **MCP: List Servers**, trust the reviewed workspace configuration, and
   start only the servers needed for the task.

## MCP authentication and security

- The Azure MCP server runs the official `@azure/mcp` package through `npx` and
  uses the developer's Azure identity. The current npm package requires Node.js
  22 or later. Sign in with Azure CLI or the Azure VS Code extension before
  invoking tools. The shared server starts in read-only mode and disables Azure
  MCP telemetry; its configuration contains no tenant ID, subscription ID, or
  token.
- The GitHub MCP server uses GitHub's official remote endpoint. VS Code handles
  the supported authentication flow; no PAT is committed.
- MCP tools act with the signed-in user's permissions. Review tool arguments and
  keep Azure/GitHub access least-privileged. Use the repository's guarded scripts
  and workflows, not MCP, for deployment mutations.
- Local MCP servers execute code on the workstation. Review the publisher and
  configuration before accepting VS Code's trust prompt.

## Learn more

- [VS Code agent customization](https://code.visualstudio.com/docs/copilot/customization/overview)
- [VS Code custom instructions](https://code.visualstudio.com/docs/copilot/customization/custom-instructions)
- [VS Code custom agents](https://code.visualstudio.com/docs/copilot/customization/custom-agents)
- [VS Code prompt files](https://code.visualstudio.com/docs/copilot/customization/prompt-files)
- [VS Code agent skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills)
- [VS Code MCP servers](https://code.visualstudio.com/docs/copilot/customization/mcp-servers)
- [Azure MCP Server](https://learn.microsoft.com/azure/developer/azure-mcp-server/)
- [GitHub MCP Server](https://github.com/github/github-mcp-server)