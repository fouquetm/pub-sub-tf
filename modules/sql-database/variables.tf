variable "base_name" {
  description = "The base name for the resources"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources into"
  type        = string
}

variable "location" {
  description = "The Azure region to deploy the resources into"
  type        = string
}

variable "key_vault_id" {
  description = "The ID of the Key Vault to store secrets in"
  type        = string
}

variable "mssql_server_name" {
  description = "The name of the SQL Server to create the database in"
  type        = string
  default     = null
}

variable "sqlsrv_login" {
  description = "The login for the SQL Server"
  type        = string
  default     = "sqladmin"
}

variable "allows_azure_services_to_access_server" {
  description = "Allow Azure services to access the SQL Server"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "The name of the database to create"
  type        = string
  default     = "RabbitMqDemo"
}
