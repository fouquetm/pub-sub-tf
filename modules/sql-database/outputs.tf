output "mssql_server_name" {
  description = "The name of the SQL Server"
  value       = var.mssql_server_name != null ? data.azurerm_mssql_server.main[0].name : azurerm_mssql_server.main[0].name
}

output "mssql_server_id" {
  description = "The ID of the SQL Server"
  value       = var.mssql_server_name != null ? data.azurerm_mssql_server.main[0].id : azurerm_mssql_server.main[0].id
}

output "database_id" {
  description = "The ID of the SQL Database"
  value       = azurerm_mssql_database.main.id
}

output "database_connection_string" {
  description = "The connection string for the SQL Database"
  value       = azurerm_key_vault_secret.database-connection-string.value
  sensitive   = true
}

output "allows_azure_services_to_access_server" {
  description = "Allow Azure services to access the SQL Server"
  value       = var.allows_azure_services_to_access_server
}

output "database_connection_string_secret_name" {
  description = "The Key Vault secret name used to store the connection string for the SQL Database"
  value       = azurerm_key_vault_secret.database-connection-string.name
}

output "database_connection_string_secret_id" {
  description = "The Key Vault secret ID used to store the connection string for the SQL Database"
  value       = azurerm_key_vault_secret.database-connection-string.id
}