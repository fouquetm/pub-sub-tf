data "azurerm_client_config" "current" {
}

data "azurerm_resource_group" "main" {
  name = "rg-${var.project}-${var.environment}"
}

data "azurerm_container_registry" "main" {
  name = "acrmaalsimfolabs"
  resource_group_name = data.azurerm_resource_group.main.name
}