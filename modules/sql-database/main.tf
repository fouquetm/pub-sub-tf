resource "random_password" "sqlsrv_password" {
  length  = 16
  special = true
  upper   = true
}

resource "azurerm_key_vault_secret" "sql-srv-password" {
  count        = var.mssql_server_name != null ? 0 : 1
  name         = "sql-srv-password"
  value        = random_password.sqlsrv_password.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "sql-srv-login" {
  count        = var.mssql_server_name != null ? 0 : 1
  name         = "sql-srv-login"
  value        = var.sqlsrv_login
  key_vault_id = var.key_vault_id
}

resource "azurerm_mssql_server" "main" {
  count                        = var.mssql_server_name != null ? 0 : 1
  name                         = "sqlsrv-${var.base_name}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sqlsrv_login
  administrator_login_password = random_password.sqlsrv_password.result
}

data "azurerm_mssql_server" "main" {
  count               = var.mssql_server_name != null ? 1 : 0
  name                = var.mssql_server_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_mssql_firewall_rule" "azure_services" {
  count            = var.allows_azure_services_to_access_server ? 1 : 0
  server_id        = var.mssql_server_name != null ? data.azurerm_mssql_server.main[0].id : azurerm_mssql_server.main[0].id
  name             = "AllowAllWindowsAzureIps"
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "main" {
  name         = var.database_name
  server_id    = var.mssql_server_name != null ? data.azurerm_mssql_server.main[0].id : azurerm_mssql_server.main[0].id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  max_size_gb  = 2
  sku_name     = "Basic"
}

resource "azurerm_key_vault_secret" "database-connection-string" {
  name         = "${var.database_name}-sql-connection-string"
  value        = "Server=tcp:${var.mssql_server_name != null ? data.azurerm_mssql_server.main[0].fully_qualified_domain_name : azurerm_mssql_server.main[0].fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.sqlsrv_login};Password=${random_password.sqlsrv_password.result};Connection Timeout=30;"
  key_vault_id = var.key_vault_id
}
