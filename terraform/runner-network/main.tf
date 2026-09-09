# =============================================================================
# Network boundary for GitHub-hosted larger runners that deploy Microsoft Fabric.
# =============================================================================
locals {
  runner_subnet_name           = "snet-${var.name_prefix}-runners"
  private_endpoint_subnet_name = "snet-${var.name_prefix}-private-endpoints"

  # GitHub recommends domain-based controls populated from api.github.com/meta;
  # its static IP template was retired after July 1, 2026. These stable wildcard
  # roots cover checkout, action downloads, OIDC, logs, artifacts, and releases.
  # https://docs.github.com/en/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization#dnsdomain-control-recommended
  github_fqdns = distinct(concat([
    "github.com",
    "api.github.com",
    "*.github.com",
    "*.githubapp.com",
    "*.githubusercontent.com",
    "*.actions.githubusercontent.com",
    "codeload.github.com",
    "ghcr.io",
    "*.pkg.github.com",
    "pkg-containers.githubusercontent.com",
    "results-receiver.actions.githubusercontent.com",
    "objects.githubusercontent.com",
    "objects-origin.githubusercontent.com",
    "github-releases.githubusercontent.com",
    "github-registry-files.githubusercontent.com",
    "release-assets.githubusercontent.com",
    "*.blob.core.windows.net",
    # GitHub's current VNet metadata explicitly requires this broader wildcard.
    # Review api.github.com/meta regularly before narrowing or changing it.
    "*.core.windows.net",
    "*.web.core.windows.net",
    "api.snapcraft.io",
    ], [
    var.github_enterprise_hostname,
    "*.${var.github_enterprise_hostname}",
    "*.actions.${var.github_enterprise_hostname}",
    "*.pages.${var.github_enterprise_hostname}",
    "*.githubassets.com",
    "auth.ghe.com",
  ]))

  terraform_fqdns = [
    "registry.terraform.io",
    "releases.hashicorp.com",
    "checkpoint-api.hashicorp.com",
  ]

  fabric_fqdns = [
    "api.fabric.microsoft.com",
    "*.fabric.microsoft.com",
    "*.powerbi.com",
    "*.analysis.windows.net",
    "*.pbidedicated.windows.net",
  ]
}

resource "azurerm_resource_provider_registration" "github_network" {
  name = "GitHub.Network"
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.virtual_network_address_space
  tags                = var.tags
}

# GitHub requires an otherwise empty subnet delegated to
# GitHub.Network/networkSettings. The service association link created later
# prevents accidental deletion while the network configuration is in use.
resource "azurerm_subnet" "runners" {
  name                 = local.runner_subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.runner_subnet_prefix]

  delegation {
    name = "github-actions"

    service_delegation {
      name    = "GitHub.Network/networkSettings"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  depends_on = [azurerm_resource_provider_registration.github_network]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.firewall_subnet_prefix]
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = local.private_endpoint_subnet_name
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_endpoint_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

# GitHub never requires inbound connections to a hosted runner and recommends
# explicitly blocking them because the runner NIC participates in the VNet:
# https://docs.github.com/en/organizations/managing-organization-settings/about-azure-private-networking-for-github-hosted-runners-in-your-organization#about-network-communication
resource "azurerm_network_security_group" "runners" {
  name                = "nsg-${var.name_prefix}-runners"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "runners" {
  subnet_id                 = azurerm_subnet.runners.id
  network_security_group_id = azurerm_network_security_group.runners.id
}

resource "azapi_resource" "firewall_public_ip" {
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  name      = "pip-${var.name_prefix}-firewall"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location
  tags      = var.tags
  body = {
    sku = {
      name = "Standard"
      tier = "Regional"
    }
    properties = {
      publicIPAddressVersion   = "IPv4"
      publicIPAllocationMethod = "Static"
    }
  }
  response_export_values = ["properties.ipAddress"]
}

resource "azurerm_firewall_policy" "this" {
  name                     = "fwpol-${var.name_prefix}"
  location                 = azurerm_resource_group.this.location
  resource_group_name      = azurerm_resource_group.this.name
  sku                      = "Standard"
  threat_intelligence_mode = "Deny"
  tags                     = var.tags

  dns {
    proxy_enabled = true
  }
}

resource "azurerm_firewall" "this" {
  name                = "fw-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azapi_resource.firewall_public_ip.id
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "runner_egress" {
  name               = "rcg-${var.name_prefix}-runner-egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  # Fabric requires both PowerBI and Sql tags for Warehouse connectivity; a
  # datawarehouse.fabric.microsoft.com endpoint can resolve into either tag.
  # Entra and ARM tags cover OIDC login and capacity control.
  # https://learn.microsoft.com/fabric/data-warehouse/connectivity#allow-azure-service-tags-through-firewall
  # https://learn.microsoft.com/fabric/security/security-service-tags
  network_rule_collection {
    name     = "azure-and-fabric-service-tags"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "azure-control-and-fabric-rest"
      protocols             = ["TCP"]
      source_addresses      = [var.runner_subnet_prefix]
      destination_addresses = ["AzureActiveDirectory", "AzureResourceManager", "PowerBI"]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "fabric-warehouse-sql"
      protocols             = ["TCP"]
      source_addresses      = [var.runner_subnet_prefix]
      destination_addresses = ["PowerBI", "Sql"]
      destination_ports     = ["1433"]
    }
  }

  application_rule_collection {
    name     = "deployment-fqdns"
    priority = 200
    action   = "Allow"

    rule {
      name              = "github-actions"
      source_addresses  = [var.runner_subnet_prefix]
      destination_fqdns = local.github_fqdns

      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name              = "terraform-distribution"
      source_addresses  = [var.runner_subnet_prefix]
      destination_fqdns = local.terraform_fqdns

      protocols {
        type = "Https"
        port = 443
      }
    }

    # The Fabric allowlist requires TCP 443 for its public workload endpoints:
    # https://learn.microsoft.com/fabric/security/fabric-allow-list-urls
    rule {
      name              = "fabric-control-plane"
      source_addresses  = [var.runner_subnet_prefix]
      destination_fqdns = local.fabric_fqdns

      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

# Azure Firewall explicit proxy carries HTTP/S only. This repository also opens
# a Warehouse TDS connection on TCP 1433, so a UDR sends all runner egress
# through the firewall's transparent path instead:
# https://learn.microsoft.com/azure/firewall/explicit-proxy
resource "azurerm_route_table" "runners" {
  name                = "rt-${var.name_prefix}-runners"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  route {
    name                   = "default-through-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.this.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "runners" {
  subnet_id      = azurerm_subnet.runners.id
  route_table_id = azurerm_route_table.runners.id
}

# Larger runners are ephemeral, so the Fabric stack cannot retain local state.
# AzAPI keeps this keyless account on the ARM control plane; AzureRM otherwise
# polls Blob with an access key after creation, which fails by design here.
resource "azapi_resource" "state" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = var.state_storage_account_name
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location
  tags      = var.tags
  body = {
    kind = "StorageV2"
    sku = {
      name = "Standard_LRS"
    }
    properties = {
      allowBlobPublicAccess        = false
      allowCrossTenantReplication  = false
      allowSharedKeyAccess         = false
      defaultToOAuthAuthentication = true
      isHnsEnabled                 = false
      isSftpEnabled                = false
      keyPolicy                    = { keyExpirationPeriodInDays = 90 }
      minimumTlsVersion            = "TLS1_2"
      publicNetworkAccess          = "Disabled"
      supportsHttpsTrafficOnly     = true
      isLocalUserEnabled           = false
      routingPreference            = { routingChoice = "MicrosoftRouting" }
      sasPolicy                    = { sasExpirationPeriod = "01.00:00:00", expirationAction = "Log" }
      accessTier                   = "Hot"
      dnsEndpointType              = "Standard"
      allowedCopyScope             = "AAD"
      encryption = {
        keySource                       = "Microsoft.Storage"
        requireInfrastructureEncryption = true
        services = {
          blob = { enabled = true, keyType = "Account" }
          file = { enabled = true, keyType = "Account" }
        }
      }
    }
  }
}

# Blob versioning and retention are also configured through ARM.
resource "azapi_resource" "state_blob_service" {
  type      = "Microsoft.Storage/storageAccounts/blobServices@2023-05-01"
  name      = "default"
  parent_id = azapi_resource.state.id
  body = {
    properties = {
      isVersioningEnabled = true
      deleteRetentionPolicy = {
        enabled              = true
        days                 = 30
        allowPermanentDelete = false
      }
      containerDeleteRetentionPolicy = {
        enabled = true
        days    = 30
      }
    }
  }
}

# Use the ARM container resource rather than the Blob data-plane API so this
# one-time bootstrap can create the container after public access is disabled.
resource "azapi_resource" "state_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = var.state_container_name
  parent_id = azapi_resource.state_blob_service.id
  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "${var.name_prefix}-blob"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "state_blob" {
  name                = "pe-${var.name_prefix}-state-blob"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "state-blob"
    private_connection_resource_id = azapi_resource.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "state-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_role_assignment" "state_blob_data" {
  scope                            = azapi_resource.state_container.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = var.deployment_principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# The deployment canary reads the live Firewall Policy to detect drift without
# granting CI permission to change the runner network.
resource "azurerm_role_assignment" "runner_network_reader" {
  scope                            = azurerm_resource_group.this.id
  role_definition_name             = "Reader"
  principal_id                     = var.deployment_principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_log_analytics_workspace" "firewall" {
  name                = "log-${var.name_prefix}-firewall"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "firewall-logs"
  target_resource_id         = azurerm_firewall.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.firewall.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# GitHub's documented ARM payload binds the enterprise/organization business ID
# to the delegated subnet. Create this last because it applies a service
# association link that intentionally protects the subnet from incompatible changes.
resource "azapi_resource" "github_network_settings" {
  type      = "GitHub.Network/networkSettings@2024-04-02"
  name      = "ghnet-${var.name_prefix}"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location
  body = {
    properties = {
      businessId = var.github_business_database_id
      subnetId   = azurerm_subnet.runners.id
    }
  }
  response_export_values = ["tags.GitHubId", "properties.provisioningState"]

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.runners,
    azurerm_subnet_route_table_association.runners,
  ]
}