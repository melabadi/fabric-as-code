# =============================================================================
# Identity and GitHub organization inputs.
# =============================================================================
variable "tenant_id" {
  type        = string
  description = "Microsoft Entra tenant containing the Azure subscription and deployment identity."

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription in which the runner network is provisioned."

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "deployment_principal_object_id" {
  type        = string
  description = "Object ID of the OIDC service principal used by the Fabric deployment workflow."

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.deployment_principal_object_id))
    error_message = "deployment_principal_object_id must be a service-principal object GUID, not its client ID."
  }
}

variable "github_business_database_id" {
  type        = string
  description = "Numeric GraphQL databaseId of the GitHub enterprise or organization that owns the network configuration."

  validation {
    condition     = can(regex("^[0-9]+$", var.github_business_database_id))
    error_message = "github_business_database_id must contain only digits."
  }
}

variable "github_enterprise_hostname" {
  type        = string
  description = "Dedicated GHE.com hostname whose Actions endpoints must be allowed through Azure Firewall."
  default     = "example.ghe.com"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.ghe\\.com$", var.github_enterprise_hostname))
    error_message = "github_enterprise_hostname must be a dedicated GHE.com hostname without a URL scheme."
  }
}

variable "github_data_residency_geography" {
  type        = string
  description = "GitHub hosting geography used to validate the larger runner's Azure region."
  default     = "us"

  validation {
    condition     = contains(["github.com", "us", "eu", "australia", "japan"], lower(var.github_data_residency_geography))
    error_message = "github_data_residency_geography must be github.com, us, eu, australia, or japan."
  }
}

# GHE.com data-residency runner regions differ from GitHub.com. The selected
# geography constrains the x64 runner regions below. Source:
# https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom#supported-regions-for-azure-private-networking
variable "location" {
  type        = string
  description = "Azure region supported by GitHub-hosted larger-runner VNet injection."
  default     = "westus3"

  validation {
    condition = contains(lookup({
      "github.com" = [
        "australiaeast", "brazilsouth", "canadacentral", "canadaeast",
        "centralus", "eastasia", "eastus", "eastus2", "francecentral",
        "germanywestcentral", "japanwest", "koreacentral", "northcentralus",
        "northeurope", "norwayeast", "southcentralus", "southeastasia",
        "southindia", "swedencentral", "switzerlandnorth", "uksouth",
        "ukwest", "westus", "westus2", "westus3",
      ]
      "us"        = ["centralus", "eastus2", "westus3"]
      "eu"        = ["francecentral", "swedencentral", "germanywestcentral", "northeurope"]
      "australia" = ["australiaeast", "australiacentral"]
      "japan"     = ["japaneast", "japanwest"]
    }, lower(var.github_data_residency_geography), []), lower(var.location))
    error_message = "location must support x64 GitHub-hosted runners in the selected GitHub data-residency geography."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the runner network, firewall, monitoring, and state backend."
  default     = "rg-example-fabric-runner"
}

variable "name_prefix" {
  type        = string
  description = "Short lowercase prefix used for regional network resource names."
  default     = "example-fabric"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-21 lowercase letters, numbers, or hyphens and start with a letter."
  }
}

variable "state_storage_account_name" {
  type        = string
  description = "Globally unique storage account name for the Fabric Terraform remote state."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "state_storage_account_name must be 3-24 lowercase letters or numbers."
  }
}

variable "state_container_name" {
  type        = string
  description = "Private Blob container holding environment-scoped Terraform state objects."
  default     = "tfstate"

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.state_container_name)) &&
      !strcontains(var.state_container_name, "--")
    )
    error_message = "state_container_name must be a valid 3-63 character Azure Blob container name."
  }
}

# A /24 provides 251 usable addresses. GitHub recommends sizing the subnet for
# maximum runner concurrency plus a 30 percent buffer:
# https://docs.github.com/en/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization#configuring-your-azure-resources
variable "virtual_network_address_space" {
  type        = list(string)
  description = "Address space for the runner virtual network."
  default     = ["10.42.0.0/16"]
}

variable "runner_subnet_prefix" {
  type        = string
  description = "CIDR delegated exclusively to GitHub-hosted larger-runner network interfaces."
  default     = "10.42.0.0/24"
}

variable "firewall_subnet_prefix" {
  type        = string
  description = "CIDR for AzureFirewallSubnet; Azure Firewall requires at least /26."
  default     = "10.42.1.0/26"
}

variable "private_endpoint_subnet_prefix" {
  type        = string
  description = "CIDR for the Terraform state storage private endpoint."
  default     = "10.42.2.0/27"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to the Azure runner-network resources."
  default = {
    managedBy = "fabric-as-code"
    workload  = "github-hosted-runner"
  }
}