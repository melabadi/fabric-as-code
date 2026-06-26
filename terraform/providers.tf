# =============================================================================
# providers.tf — provider requirements and configuration.
#
# Auth: both providers reuse your "az login" session by default (Azure CLI).
#   For CI/CD, set ARM_* / FABRIC_* env vars for a service principal instead.
# =============================================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# The Microsoft Fabric provider. Uses Azure CLI auth by default.
provider "fabric" {}
