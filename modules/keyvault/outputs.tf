output "key_vault_id" {
  description = "The id of the key vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}
