# 1. Tell Terraform to use Azure
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# 2. Create a "Resource Group" (A folder for your project in Azure)
resource "azurerm_resource_group" "poc_rg" {
  name     = "Gateway-POC-RG"
  location = "East US"
}
