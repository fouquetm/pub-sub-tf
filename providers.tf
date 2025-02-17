terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.19.0"
    }
  }

  backend "azurerm" {
    resource_group_name   = "rg-maalsi-24-2-mfolabs"
    storage_account_name  = "stmaalsi242mfouquettf"
    container_name        = "tfstates"
    key                   = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {    
  }
  subscription_id = "10ce0944-5960-42ed-8657-1a8177030014"
}