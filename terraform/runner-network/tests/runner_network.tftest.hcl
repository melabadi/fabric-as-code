# Mocked plans verify the security and connectivity contract without creating
# Azure resources or requiring a GitHub organization connection.
mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  tenant_id                      = "00000000-0000-0000-0000-000000000001"
  subscription_id                = "00000000-0000-0000-0000-000000000002"
  deployment_principal_object_id = "00000000-0000-0000-0000-000000000003"
  github_business_database_id    = "12345678"
  state_storage_account_name     = "fabricghateststate"
}

run "runner_network_contract" {
  command = plan

  assert {
    condition     = azurerm_subnet.runners.delegation[0].service_delegation[0].name == "GitHub.Network/networkSettings"
    error_message = "The runner subnet must remain delegated to GitHub.Network/networkSettings."
  }

  assert {
    condition = anytrue([
      for rule in azurerm_network_security_group.runners.security_rule :
      rule.direction == "Inbound" && rule.access == "Deny"
    ])
    error_message = "The runner subnet must reject inbound connections."
  }

  assert {
    condition = anytrue([
      for route in azurerm_route_table.runners.route :
      route.address_prefix == "0.0.0.0/0" && route.next_hop_type == "VirtualAppliance"
    ])
    error_message = "All runner internet egress must route through Azure Firewall."
  }

  assert {
    condition = alltrue([
      for tag in ["AzureActiveDirectory", "AzureResourceManager", "PowerBI", "Sql"] :
      contains(flatten([
        for collection in azurerm_firewall_policy_rule_collection_group.runner_egress.network_rule_collection : [
          for rule in collection.rule : rule.destination_addresses
        ]
      ]), tag)
    ])
    error_message = "Firewall network rules must retain the Azure and Fabric service tags needed by the deployment."
  }

  assert {
    condition = anytrue(flatten([
      for collection in azurerm_firewall_policy_rule_collection_group.runner_egress.network_rule_collection : [
        for rule in collection.rule :
        rule.name == "fabric-warehouse-sql" &&
        length(rule.protocols) == 1 &&
        contains(rule.protocols, "TCP") &&
        contains(rule.destination_addresses, "PowerBI") &&
        contains(rule.destination_addresses, "Sql") &&
        contains(rule.destination_ports, "1433")
      ]
    ]))
    error_message = "Warehouse TDS must allow both PowerBI and Sql service tags on TCP 1433."
  }

  assert {
    condition = alltrue([
      for fqdn in ["github.com", "*.githubapp.com", "ghcr.io", "example.ghe.com", "*.example.ghe.com", "auth.ghe.com", "*.web.core.windows.net", "registry.terraform.io", "api.fabric.microsoft.com"] :
      contains(flatten([
        for collection in azurerm_firewall_policy_rule_collection_group.runner_egress.application_rule_collection : [
          for rule in collection.rule : rule.destination_fqdns
        ]
      ]), fqdn)
    ])
    error_message = "Firewall application rules must retain GitHub, Terraform, and Fabric control-plane endpoints."
  }

  assert {
    condition = (
      azapi_resource.state.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.state.body.properties.allowSharedKeyAccess == false &&
      azapi_resource.state_blob_service.body.properties.isVersioningEnabled == true
    )
    error_message = "Terraform state must use private, Entra-only, versioned Blob storage."
  }

  assert {
    condition     = azapi_resource.github_network_settings.body.properties.businessId == "12345678"
    error_message = "GitHub network settings must bind the delegated subnet to the configured enterprise or organization."
  }

  assert {
    condition = (
      azurerm_role_assignment.runner_network_reader.role_definition_name == "Reader" &&
      azurerm_role_assignment.runner_network_reader.principal_id == "00000000-0000-0000-0000-000000000003"
    )
    error_message = "The deployment principal must have read-only visibility into live runner-network policy."
  }
}

run "reject_region_outside_us_data_residency" {
  command = plan

  variables {
    location = "northeurope"
  }

  expect_failures = [var.location]
}

run "reject_invalid_container_name" {
  command = plan

  variables {
    state_container_name = "bad--name"
  }

  expect_failures = [var.state_container_name]
}