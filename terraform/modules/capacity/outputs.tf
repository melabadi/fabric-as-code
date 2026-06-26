output "capacity_resource_id" {
  description = "ARM resource ID of the capacity."
  value       = azurerm_fabric_capacity.this.id
}

output "capacity_guid" {
  description = "Fabric capacity object GUID."
  value       = data.fabric_capacity.this.id
}
