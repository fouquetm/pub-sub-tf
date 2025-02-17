data "azurerm_client_config" "current" {
}

data "azurerm_resource_group" "main" {
  name = "rg-${var.project}-${var.environment}"
}