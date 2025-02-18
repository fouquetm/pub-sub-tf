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

module "sql-database" {
  source = "./modules/sql-database"

  base_name                              = local.base_name
  location                               = data.azurerm_resource_group.main.location
  resource_group_name                    = data.azurerm_resource_group.main.name
  key_vault_id                           = module.key_vault.key_vault_id
  sqlsrv_login                           = "sqladmin"
  database_name                          = "RabbitMqDemo"
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
    key_vault_secret_id = module.sql-database.database_connection_string_secret_id
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
}
