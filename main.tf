locals {
  base_name = "${var.project}-${var.environment}"
}

resource "random_string" "main" {
  length  = 18
  special = false
  upper   = false  
}

resource "azurerm_storage_account" "main" {
  name                     = "st${random_string.main.result}"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = data.azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_key_vault" "main" {
  name                        = "kv-${local.base_name}"
  location                    = data.azurerm_resource_group.main.location
  resource_group_name         = data.azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [   
      "Get",
      "List",
      "Set",
      "Delete"
    ]
  }
}

resource "random_string" "sqlsrv_password" {
  length  = 16
  special = true
  upper   = true  
}

resource "azurerm_key_vault_secret" "sql-srv-password" {
  name         = "sql-srv-password"
  value        = random_string.sqlsrv_password.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [ azurerm_key_vault.main ]
}

resource "azurerm_key_vault_secret" "sql-srv-login" {
  name         = "sql-srv-login"
  value        = var.sqlsrv_login
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [ azurerm_key_vault.main ]
}

resource "azurerm_mssql_server" "main" {
  name                         = "sqlsrv-${local.base_name}"
  resource_group_name          = data.azurerm_resource_group.main.name
  location                     = data.azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sqlsrv_login
  administrator_login_password = random_string.sqlsrv_password.result
}

resource "azurerm_mssql_database" "rabbitmqdemo" {
  name         = "RabbitMqDemo"
  server_id    = azurerm_mssql_server.main.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  max_size_gb  = 2
  sku_name     = "Basic"

  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = true
  }
}