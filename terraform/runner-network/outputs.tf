output "github_network_settings_id" {
  description = "GitHubId entered under Organization Settings > Hosted compute networking > Azure private network."
  value       = try(azapi_resource.github_network_settings.output.tags.GitHubId, null)
}

output "github_network_settings_resource_id" {
  description = "Azure resource ID of GitHub.Network/networkSettings."
  value       = azapi_resource.github_network_settings.id
}

output "runner_subnet_id" {
  description = "Delegated subnet into which GitHub injects larger-runner network interfaces."
  value       = azurerm_subnet.runners.id
}

output "firewall_public_ip_address" {
  description = "Stable deployment egress address to add to both Fabric workspace IP allowlists."
  value       = azapi_resource.firewall_public_ip.output.properties.ipAddress
}

output "fabric_backend_config" {
  description = "Non-secret values consumed by deploy-terraform.ps1 for the private Azure Blob backend."
  value = {
    resource_group_name  = azurerm_resource_group.this.name
    storage_account_name = azapi_resource.state.name
    container_name       = var.state_container_name
  }
}