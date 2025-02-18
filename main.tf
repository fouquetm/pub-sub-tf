locals {
  base_name = "${var.project}-${var.environment}"
}

module "key_vault" {
  source = "./modules/keyvault"

  base_name               = local.base_name
  location                = data.azurerm_resource_group.main.location
  resource_group_name     = data.azurerm_resource_group.main.name
  tenant_id               = data.azurerm_client_config.current.tenant_id
  administrator_object_id = data.azurerm_client_config.current.object_id
}

moved { # faire un terraform init pour prise en compte
  from = azurerm_key_vault.main
  to   = module.key_vault.azurerm_key_vault.main
}

resource "random_password" "sqlsrv_password" {
  length  = 16
  special = true
  upper   = true
}

resource "azurerm_key_vault_secret" "sql-srv-password" {
  name         = "sql-srv-password"
  value        = random_password.sqlsrv_password.result
  key_vault_id = module.key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "sql-srv-login" {
  name         = "sql-srv-login"
  value        = var.sqlsrv_login
  key_vault_id = module.key_vault.key_vault_id
}

resource "azurerm_mssql_server" "main" {
  name                         = "sqlsrv-${local.base_name}"
  resource_group_name          = data.azurerm_resource_group.main.name
  location                     = data.azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sqlsrv_login
  administrator_login_password = random_password.sqlsrv_password.result
}

resource "azurerm_mssql_firewall_rule" "azure_services" {
  server_id        = azurerm_mssql_server.main.id
  name             = "AllowAllWindowsAzureIps"
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
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

resource "azurerm_key_vault_secret" "sql-srv-connection-string" {
  name         = "sql-srv-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=RabbitMqDemo;Persist Security Info=False;User ID=${azurerm_mssql_server.main.administrator_login};Password=${azurerm_mssql_server.main.administrator_login_password};Connection Timeout=30;"
  key_vault_id = module.key_vault.key_vault_id
}

resource "random_password" "rabbitmq_password" {
  length  = 16
  special = true
  upper   = true
}

resource "azurerm_key_vault_secret" "rabbitmq-login" {
  name         = "rabbitmq-login"
  value        = "admin"
  key_vault_id = module.key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "rabbitmq-password" {
  name         = "rabbitmq-password"
  value        = random_password.rabbitmq_password.result
  key_vault_id = module.key_vault.key_vault_id
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
  ip_address_type     = "None"

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

resource "azurerm_user_assigned_identity" "main" {
  name                = "mid-${local.base_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_role_assignment" "kv_mid_get_secrets" {
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_role_assignment" "acr_mid_pull_images" {
  scope                = data.azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_container_app_environment" "main" {
  name                = "cae-${local.base_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_container_app" "api" {
  name                         = "ca-api-${local.base_name}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"


  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.main.id
    ]
  }

  registry {
    server   = data.azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.main.id
  }

  secret {
    name                = "sql-srv-connection-string"
    key_vault_secret_id = azurerm_key_vault_secret.sql-srv-connection-string.id
    identity            = azurerm_user_assigned_identity.main.id
  }
  secret {
    name                = "rabbitmq-login"
    key_vault_secret_id = azurerm_key_vault_secret.rabbitmq-login.id
    identity            = azurerm_user_assigned_identity.main.id
  }
  secret {
    name                = "rabbitmq-password"
    key_vault_secret_id = azurerm_key_vault_secret.rabbitmq-password.id
    identity            = azurerm_user_assigned_identity.main.id
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 80
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 10
    container {
      name   = "api"
      image  = "acrmaalsimfolabs.azurecr.io/matthieuf/pubsub-api:1.3"
      cpu    = 0.5
      memory = "1Gi"

      startup_probe {
        transport               = "TCP"
        port                    = 80
        path                    = "/api/Product/productlist"
        initial_delay           = 10
        interval_seconds        = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "TCP"
        port                    = 80
        path                    = "/api/Product/productlist"
        initial_delay           = 10
        interval_seconds        = 5
        failure_count_threshold = 3
        success_count_threshold = 1
      }

      liveness_probe {
        transport               = "TCP"
        port                    = 80
        path                    = "/api/Product/productlist"
        initial_delay           = 10
        interval_seconds        = 5
        failure_count_threshold = 3
      }

      env {
        name  = "RabbitMQ__Hostname"
        value = azurerm_container_group.rabbitmq.fqdn
      }
      env {
        name        = "RabbitMQ__Username"
        secret_name = "rabbitmq-login"
      }
      env {
        name        = "RabbitMQ__Password"
        secret_name = "rabbitmq-password"
      }
      env {
        name        = "ConnectionStrings__DefaultConnection"
        secret_name = "sql-srv-connection-string"
      }
    }
  }

  depends_on = [
    azurerm_user_assigned_identity.main,
    azurerm_key_vault_secret.sql-srv-connection-string,
    azurerm_key_vault_secret.rabbitmq-login,
    azurerm_key_vault_secret.rabbitmq-password,
    azurerm_mssql_firewall_rule.azure_services
  ]
}
