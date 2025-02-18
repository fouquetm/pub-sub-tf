variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
}

variable "project" {
  description = "The project name"
  type        = string
  default     = "maalsi-24-2"
}

variable "environment" {
  description = "The environment name"
  type        = string
  default     = "mfolabs"
}

variable "sqlsrv_login" {
  description = "The SQL Server administrator login"
  type        = string
  default     = "sqladmin"
}

variable "acr_name" {
  description = "The Azure Container Registry name"
  type        = string
  default     = "acrmaalsimfolabs"
}
