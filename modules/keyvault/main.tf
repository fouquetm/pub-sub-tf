resource "azurerm_key_vault" "main" {
  name                        = "kv-${var.base_name}"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = var.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name                  = "standard"
  enable_rbac_authorization = true
}

# doc azure : key vault built-in roles : https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations
resource "azurerm_role_assignment" "kv_current_id_secrets_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.administrator_object_id
}

resource "azurerm_role_assignment" "kv_current_id_certificates_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = var.administrator_object_id
}

resource "azurerm_role_assignment" "kv_current_id_crypto_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = var.administrator_object_id
}