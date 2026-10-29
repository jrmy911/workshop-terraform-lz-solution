output "resource_group_name" {
  description = "The resource group to inspect in the Azure portal."
  value       = azurerm_resource_group.workshop.name
}

output "vm_name" {
  description = "The VM to select for Azure Run Command."
  value       = azurerm_linux_virtual_machine.workshop.name
}

output "vm_private_ip" {
  description = "The VM address inside the workload subnet."
  value       = azurerm_network_interface.vm.private_ip_address
}

output "key_vault_uri" {
  description = "The Key Vault URI, reachable privately from the VNet."
  value       = azurerm_key_vault.workshop.vault_uri
}
