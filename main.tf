locals {
  base_name = "${var.project}-${var.environment}"
}

resource "azurerm_storage_account" "main" {
  name                     = replace("st${local.base_name}", "-", "")
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

resource "random_password" "sqlsrv_password" {
  length  = 16
  special = true
  upper   = true
}

resource "azurerm_key_vault_secret" "sql-srv-password" {
  name         = "sql-srv-password"
  value        = random_password.sqlsrv_password.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "sql-srv-login" {
  name         = "sql-srv-login"
  value        = var.sqlsrv_login
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_mssql_server" "main" {
  name                         = "sqlsrv-${local.base_name}"
  resource_group_name          = data.azurerm_resource_group.main.name
  location                     = data.azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sqlsrv_login
  administrator_login_password = random_password.sqlsrv_password.result
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

resource "random_password" "rabbitmq_password" {
  length  = 16
  special = true
  upper   = true
}

resource "azurerm_key_vault_secret" "rabbitmq-login" {
  name         = "rabbitmq-login"
  value        = "admin"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "rabbitmq-password" {
  name         = "rabbitmq-password"
  value        = random_password.rabbitmq_password.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_container_group" "rabbitmq" {
  name                = "ci-${local.base_name}-rbmq"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  ip_address_type     = "Public"
  dns_name_label      = "ci-${local.base_name}-rbmq"
  os_type             = "Linux"

  image_registry_credential {
    server   = data.azurerm_container_registry.main.login_server
    username = data.azurerm_container_registry.main.admin_username
    password = data.azurerm_container_registry.main.admin_password
  }

  container {
    name   = "rabbitmq"
    image  = "acrmaalsimfolabs.azurecr.io/rabbitmq:3-management"
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 5672
      protocol = "TCP"
    }

    ports {
      port     = 15672
      protocol = "TCP"
    }

    secure_environment_variables = {
      RABBITMQ_DEFAULT_USER = "admin"
      RABBITMQ_DEFAULT_PASS = random_password.rabbitmq_password.result
    }
  }

  exposed_port = [ # Expose the RabbitMQ management interface
    {
      port     = 15672
      protocol = "TCP"
    },
    {
      port     = 5672
      protocol = "TCP"
    }
  ]
}

resource "azurerm_container_group" "console" {
  name                = "ci-${local.base_name}-console"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  os_type             = "Linux"
  ip_address_type = "None"

  image_registry_credential {
    server   = data.azurerm_container_registry.main.login_server
    username = data.azurerm_container_registry.main.admin_username
    password = data.azurerm_container_registry.main.admin_password
  }

  container {
    name   = "console"
    image  = "acrmaalsimfolabs.azurecr.io/matthieuf/pubsub-console:1.0"
    cpu    = "0.5"
    memory = "1.5"

    environment_variables = {
      RabbitMQ__Hostname = azurerm_container_group.rabbitmq.fqdn
    }

    secure_environment_variables = {
      RabbitMQ__Username = "admin"
      RabbitMQ__Password = random_password.rabbitmq_password.result
    }
  }
}
