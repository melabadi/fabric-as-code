# =============================================================================
# providers.tf — versions, state backend, and provider authentication.
#
# Both providers reuse the Azure CLI session: interactive `az login` locally or
# the isolated OIDC session created by `azure/login` in GitHub Actions. Explicit
# tenant/subscription inputs prevent an authenticated shell from targeting the
# wrong environment.
#
# GitHub-hosted larger runners are ephemeral, so state must outlive each job.
# The runner-network stack creates a private Blob backend; the deployment script
# supplies its non-secret names and GitHub OIDC settings during `terraform init`.
# HashiCorp recommends OIDC plus Microsoft Entra data-plane authentication:
# https://developer.hashicorp.com/terraform/language/backend/azurerm#example-configuration-for-github
# AzureRM provider: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
# Fabric provider: https://registry.terraform.io/providers/microsoft/fabric/latest/docs
# Deployment guide: ../docs/deployment/README.md
# =============================================================================
terraform {
  # Terraform 1.9 introduced the removed block used for the SQL marker migration.
  required_version = ">= 1.9.0, < 2.0.0"

  backend "azurerm" {}

  required_providers {
    # Learn more: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # Learn more: https://registry.terraform.io/providers/microsoft/fabric/latest/docs
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.12.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  features {}
}

# Azure CLI is the provider default for local runs. GitHub Actions sets
# ARM_USE_OIDC=true so CI selects OIDC without enabling a second auth mode.
provider "fabric" {
  tenant_id = var.tenant_id
}
