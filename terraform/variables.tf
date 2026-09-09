# =============================================================================
# variables.tf — root inputs for full-platform and existing-workspace modes.
# Provide values through an environment-specific .tfvars file.
# =============================================================================

# ---- Authentication target -------------------------------------------------
# These identifiers select where the CLI-backed providers operate; they are not
# credentials and do not grant access by themselves.
variable "tenant_id" {
  type        = string
  description = "Entra ID (Azure AD) tenant that owns the subscription and capacity."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription used for authentication and optional platform provisioning."
}

# ---- Deployment mode and environment identity ------------------------------
# Platform mode creates Azure capacity infrastructure and both workspaces.
# Existing-platform mode requires workspace_id and can adopt item GUIDs.
variable "provision_platform" {
  type        = bool
  description = "Create the Azure resource group, Fabric capacity, and both role-specific workspaces when true; use existing workspace IDs when false."
  default     = false
}

variable "manage_workspaces" {
  type        = bool
  description = "Manage both role-specific Fabric workspaces on an existing capacity when provision_platform is false."
  default     = false
}

variable "deployment_environment" {
  type        = string
  description = "Stable environment label used in Azure tags and environment-specific state paths."
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.deployment_environment))
    error_message = "deployment_environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# ---- Full-platform inputs ---------------------------------------------------
# Guides: ../docs/deployment/01-capacity.md
#         ../docs/deployment/02-workspaces.md
# Conditional validations make capacity_name, capacity_admins, and a non-empty
# workspace_name mandatory only when provision_platform is true.
variable "resource_group" {
  type        = string
  description = "Resource group containing the Fabric capacity; created when provision_platform is true."
  default     = null

  validation {
    condition     = var.resource_group != null && try(trimspace(var.resource_group), "") != ""
    error_message = "resource_group is required in every deployment mode."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the resource group and Fabric capacity."
  default     = "westeurope"
}

variable "capacity_name" {
  type        = string
  description = "Fabric capacity ARM resource name used for provisioning and active-state management."
  default     = null

  validation {
    condition     = var.capacity_name != null && can(regex("^[a-z][a-z0-9]{2,62}$", var.capacity_name))
    error_message = "capacity_name is required and must be 3-63 lowercase letters and numbers, starting with a letter."
  }
}

variable "fabric_capacity_id" {
  type        = string
  description = "Existing Fabric capacity object GUID used when Terraform manages workspaces without provisioning the platform."
  default     = null

  validation {
    condition = var.provision_platform || !var.manage_workspaces || can(regex(
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
      var.fabric_capacity_id
    ))
    error_message = "fabric_capacity_id must be a Fabric capacity GUID when manage_workspaces is true and provision_platform is false."
  }
}

variable "capacity_sku" {
  type        = string
  description = "Fabric capacity SKU used when provision_platform is true."
  default     = "F2"

  validation {
    condition     = can(regex("^F(2|4|8|16|32|64|128|256|512|1024|2048)$", var.capacity_sku))
    error_message = "capacity_sku must be one of F2, F4, F8, F16, F32, F64, F128, F256, F512, F1024, or F2048."
  }
}

variable "capacity_admins" {
  type        = list(string)
  description = "Capacity administrator UPNs or service-principal object IDs used when provision_platform is true."
  default     = []

  validation {
    condition = !var.provision_platform || (
      length(var.capacity_admins) > 0 && alltrue([
        for admin in var.capacity_admins : trimspace(admin) != ""
      ])
    )
    error_message = "capacity_admins must contain at least one non-empty value when provision_platform is true."
  }
}

variable "workspace_name" {
  type        = string
  description = "CI/CD deployment workspace display name used when provision_platform is true."
  default     = "Fabric-as-Code Dev"

  validation {
    condition     = !(var.provision_platform || var.manage_workspaces) || trimspace(var.workspace_name) != ""
    error_message = "workspace_name must not be empty when Terraform manages workspaces."
  }
}

variable "workspace_description" {
  type        = string
  description = "CI/CD deployment workspace description used when provision_platform is true."
  default     = "Workspace deployed by the fabric-as-code CI/CD pipeline."
}

variable "git_workspace_name" {
  type        = string
  description = "Git-mirrored authoring workspace display name used when provision_platform is true."
  default     = "Fabric-as-Code Git"

  validation {
    condition = !(var.provision_platform || var.manage_workspaces) || (
      trimspace(var.git_workspace_name) != "" &&
      lower(trimspace(var.git_workspace_name)) != lower(trimspace(var.workspace_name))
    )
    error_message = "git_workspace_name must not be empty or match workspace_name when Terraform manages workspaces."
  }
}

variable "git_workspace_description" {
  type        = string
  description = "Git-mirrored authoring workspace description used when provision_platform is true."
  default     = "Authoring workspace mirrored from the fabric-as-code repository."
}

# ---- Workspace access policy -----------------------------------------------
# Guide: ../docs/deployment/03-workspace-settings.md
variable "workspace_role_assignments" {
  type = map(object({
    workspaces     = optional(set(string), ["cicd"])
    principal_id   = string
    principal_type = string
    role           = string
  }))
  description = "Fabric role assignments keyed by a stable name. Each assignment can target the cicd workspace, the git workspace, or both."
  default     = {}

  validation {
    condition = alltrue([
      for assignment in values(var.workspace_role_assignments) :
      length(assignment.workspaces) > 0 &&
      length(setsubtract(assignment.workspaces, toset(["cicd", "git"]))) == 0
    ])
    error_message = "Each workspace role assignment must target cicd, git, or both."
  }

  validation {
    condition = alltrue([
      for assignment in values(var.workspace_role_assignments) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", assignment.principal_id)) &&
      contains(["Group", "ServicePrincipal", "ServicePrincipalProfile", "User"], assignment.principal_type) &&
      contains(["Admin", "Contributor", "Member", "Viewer"], assignment.role)
    ])
    error_message = "Workspace role assignments require a principal GUID, a supported principal_type, and an Admin, Member, Contributor, or Viewer role."
  }

  validation {
    condition = alltrue([
      for assignment in values(var.workspace_role_assignments) :
      !contains(assignment.workspaces, "git") ||
      var.provision_platform ||
      var.manage_workspaces ||
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.git_workspace_id))
    ])
    error_message = "A git workspace role assignment requires Terraform-managed workspaces or git_workspace_id."
  }

  validation {
    condition = length(flatten([
      for assignment in values(var.workspace_role_assignments) : [
        for workspace_name in assignment.workspaces :
        "${workspace_name}/${lower(assignment.principal_id)}"
      ]
      ])) == length(distinct(flatten([
        for assignment in values(var.workspace_role_assignments) : [
          for workspace_name in assignment.workspaces :
          "${workspace_name}/${lower(assignment.principal_id)}"
        ]
    ])))
    error_message = "A principal can have only one role assignment in each workspace."
  }
}

variable "workspace_encryption" {
  type = map(object({
    enabled        = optional(bool, true)
    key_identifier = optional(string)
  }))
  description = "Customer-managed key policy keyed by cicd or git. Set enabled=false to reset a managed workspace to Microsoft-managed encryption; omit a workspace to leave its encryption unmanaged."
  default     = {}

  validation {
    condition     = length(setsubtract(toset(keys(var.workspace_encryption)), toset(["cicd", "git"]))) == 0
    error_message = "workspace_encryption keys must be cicd or git."
  }

  validation {
    condition = alltrue([
      for policy in values(var.workspace_encryption) :
      policy.enabled
      ? can(regex("^https://[A-Za-z0-9-]+\\.(vault\\.azure\\.net|managedhsm\\.azure\\.net)/keys/[A-Za-z0-9-]+/?$", policy.key_identifier))
      : try(trimspace(policy.key_identifier), "") == ""
    ])
    error_message = "Enabled workspace encryption requires a versionless Azure Key Vault or Managed HSM key URI; disabled encryption must omit key_identifier."
  }

  validation {
    condition = !contains(keys(var.workspace_encryption), "git") || (
      var.provision_platform ||
      var.manage_workspaces ||
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.git_workspace_id))
    )
    error_message = "A git workspace encryption policy requires Terraform-managed workspaces or git_workspace_id."
  }

  validation {
    condition = !try(var.workspace_encryption["cicd"].enabled, false) || (
      var.item_deployment_profile == "p0"
    )
    error_message = "CMK on the CI/CD workspace requires item_deployment_profile = \"p0\" because the all profile contains item types outside Fabric's documented CMK support list."
  }
}

variable "workspace_security_monitoring_enabled" {
  type        = bool
  description = "Run authenticated post-deployment and scheduled checks for workspace reachability, CMK, inbound policy, and Warehouse TDS. This does not enable Fabric Workspace monitoring, whose documented setup is portal-based."
  default     = true
}

# ---- Optional workspace Git ownership --------------------------------------
# Guide: ../docs/deployment/04-git-integration.md
# Leave null when Terraform is the definition owner. When enabled, choose the
# provider-specific repository fields and a configured Fabric connection (or
# Azure DevOps Automatic credentials). PreferRemote initializes the dedicated
# authoring workspace from the repository without mixing Terraform ownership.
variable "git_integration" {
  type = object({
    provider_type           = string
    repository_name         = string
    branch_name             = string
    directory_name          = optional(string, "/fabric-git")
    initialization_strategy = optional(string, "PreferRemote")
    credentials_source      = optional(string, "ConfiguredConnection")
    connection_id           = optional(string)
    organization_name       = optional(string)
    project_name            = optional(string)
    owner_name              = optional(string)
    allow_override_items    = optional(bool, false)
  })
  description = "Optional Git configuration for the dedicated authoring workspace. Leave null when no repository mirror is needed."
  default     = null

  validation {
    condition = var.git_integration == null || (
      contains(["AzureDevOps", "GitHub"], var.git_integration.provider_type) &&
      contains(["PreferRemote", "PreferWorkspace"], var.git_integration.initialization_strategy) &&
      startswith(var.git_integration.directory_name, "/")
    )
    error_message = "git_integration must use a supported provider and initialization strategy, and directory_name must start with '/'."
  }

  validation {
    condition = var.git_integration == null || (
      var.git_integration.provider_type == "GitHub"
      ? try(trimspace(var.git_integration.owner_name), "") != "" &&
      var.git_integration.credentials_source == "ConfiguredConnection" &&
      try(trimspace(var.git_integration.connection_id), "") != ""
      : try(trimspace(var.git_integration.organization_name), "") != "" &&
      try(trimspace(var.git_integration.project_name), "") != "" &&
      contains(["Automatic", "ConfiguredConnection"], var.git_integration.credentials_source) &&
      (var.git_integration.credentials_source == "Automatic" || try(trimspace(var.git_integration.connection_id), "") != "")
    )
    error_message = "GitHub requires owner_name and a configured connection; Azure DevOps requires organization_name and project_name, plus connection_id when ConfiguredConnection is used."
  }
}

# ---- Existing workspace and optional item adoption -------------------------
# Guide: ../docs/deployment/05-content-files.md
# imports.tf consumes each non-empty item ID only in existing-workspace mode.
# Null IDs mean "create this item"; supplied IDs mean "adopt this item".
variable "item_deployment_profile" {
  type        = string
  description = "Item set deployed to CI/CD: p0 creates Lakehouse, Warehouse, and Notebook; all preserves the complete nine-item demo."
  default     = "all"

  validation {
    condition     = contains(["p0", "all"], var.item_deployment_profile)
    error_message = "item_deployment_profile must be p0 or all."
  }

  validation {
    condition = var.item_deployment_profile == "all" || alltrue([
      for id in [
        var.pipeline_id,
        var.environment_id,
        var.eventhouse_id,
        var.kql_database_id,
        var.variable_library_id,
        var.ml_experiment_id,
      ] : try(trimspace(id), "") == ""
    ])
    error_message = "Extended item adoption IDs must be empty when item_deployment_profile is p0."
  }
}

variable "workspace_id" {
  type        = string
  description = "Existing CI/CD deployment workspace GUID used when provision_platform is false."
  default     = null

  validation {
    condition     = try(trimspace(var.workspace_id), "") == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.workspace_id))
    error_message = "workspace_id must be null or a valid Fabric workspace GUID."
  }

  validation {
    condition     = var.provision_platform || var.manage_workspaces || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.workspace_id))
    error_message = "workspace_id must be a Fabric workspace GUID when Terraform does not manage workspaces."
  }

  validation {
    condition     = !var.provision_platform || try(trimspace(var.workspace_id), "") == ""
    error_message = "workspace_id must be empty when provision_platform is true."
  }
}

variable "git_workspace_id" {
  type        = string
  description = "Existing Git-mirrored authoring workspace GUID required when Git is enabled and provision_platform is false."
  default     = null

  validation {
    condition = var.git_integration == null || var.provision_platform || var.manage_workspaces || (
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.git_workspace_id))
    )
    error_message = "git_workspace_id must be a valid Fabric workspace GUID when Git is enabled and Terraform does not manage workspaces."
  }

  validation {
    condition     = try(trimspace(var.git_workspace_id), "") == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.git_workspace_id))
    error_message = "git_workspace_id must be null or a valid Fabric workspace GUID."
  }

  validation {
    condition = (
      try(trimspace(var.git_workspace_id), "") == "" ||
      try(trimspace(var.workspace_id), "") == "" ||
      try(lower(var.git_workspace_id) != lower(var.workspace_id), false)
    )
    error_message = "git_workspace_id must be different from workspace_id."
  }

  validation {
    condition     = !var.provision_platform || try(trimspace(var.git_workspace_id), "") == ""
    error_message = "git_workspace_id must be empty when provision_platform is true."
  }
}

variable "lakehouse_id" {
  type        = string
  description = "Existing Lakehouse GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "warehouse_id" {
  type        = string
  description = "Existing Warehouse GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "notebook_id" {
  type        = string
  description = "Existing Notebook GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "pipeline_id" {
  type        = string
  description = "Existing Data Pipeline GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "environment_id" {
  type        = string
  description = "Existing Environment GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "eventhouse_id" {
  type        = string
  description = "Existing Eventhouse GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "kql_database_id" {
  type        = string
  description = "Existing KQL Database GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "variable_library_id" {
  type        = string
  description = "Existing Variable Library GUID to adopt into Terraform state, or null to create it."
  default     = null
}

variable "ml_experiment_id" {
  type        = string
  description = "Existing ML Experiment GUID to adopt into Terraform state, or null to create it."
  default     = null
}

# ---- Fabric item display names ---------------------------------------------
# These names apply to both newly created and imported items.
variable "lakehouse_name" {
  type        = string
  description = "Display name of the Lakehouse managed in the target workspace."
  default     = "lh_demo"
}

variable "warehouse_name" {
  type        = string
  description = "Display name of the Warehouse managed in the target workspace."
  default     = "wh_demo"
}

variable "notebook_name" {
  type        = string
  description = "Display name of the Notebook managed in the target workspace."
  default     = "nb_demo_load"
}

variable "pipeline_name" {
  type        = string
  description = "Display name of the Data Pipeline managed in the target workspace."
  default     = "pl_demo_ingest"
}

variable "environment_name" {
  type        = string
  description = "Display name of the Spark Environment managed in the target workspace."
  default     = "env_demo_spark"
}

variable "eventhouse_name" {
  type        = string
  description = "Display name of the Eventhouse managed in the target workspace."
  default     = "eh_demo_events"
}

variable "kql_database_name" {
  type        = string
  description = "Display name of the writable KQL Database managed in the target workspace."
  default     = "kqldb_demo_events"
}

variable "variable_library_name" {
  type        = string
  description = "Display name of the Variable Library managed in the target workspace."
  default     = "vl_demo_config"
}

variable "ml_experiment_name" {
  type        = string
  description = "Display name of the ML Experiment managed in the target workspace."
  default     = "mlexp_demo_forecast"
}

# ---- Optional Warehouse data-plane deployment ------------------------------
variable "deploy_stored_procedures" {
  type        = bool
  description = "Whether to deploy the Warehouse schema/tables/stored procedures (needs pwsh + az)."
  default     = true
}

# ---- Optional workspace inbound firewall ----------------------------------
# The runner-network stack outputs the Azure Firewall public IP used here.
# Fabric documents that workspace IP rules admit REST and supported item access
# from selected public addresses:
# https://learn.microsoft.com/fabric/security/security-workspace-level-firewall-overview
variable "fabric_workspace_firewall_ip" {
  type        = string
  description = "Stable Azure Firewall public IPv4 address allowed into each managed Fabric workspace; null or empty disables workspace firewall management."
  default     = null
  nullable    = true

  validation {
    condition = (
      try(trimspace(var.fabric_workspace_firewall_ip), "") == "" ||
      can(cidrnetmask("${var.fabric_workspace_firewall_ip}/32"))
    )
    error_message = "fabric_workspace_firewall_ip must be null, empty, or a valid IPv4 address."
  }
}
# The managed rule name is fixed in main.tf so an IP rotation cannot leave an
# older deployment allow rule behind under a previous configurable name.
