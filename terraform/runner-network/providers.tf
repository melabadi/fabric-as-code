# =============================================================================
# GitHub-hosted larger-runner Azure networking bootstrap.
#
# GitHub documents that Azure VNet injection is available only to larger
# Ubuntu/Windows runners, not standard hosted runners:
# https://docs.github.com/en/organizations/managing-organization-settings/about-azure-private-networking-for-github-hosted-runners-in-your-organization
#
# GitHub.Network/networkSettings is an Azure extension resource that delegates
# a subnet to the GitHub Actions service. AzAPI manages that resource until it
# has a first-class AzureRM representation:
# https://docs.github.com/en/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization
# =============================================================================
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  features {}
}

provider "azapi" {}