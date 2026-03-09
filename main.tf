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
#3. Create a Virtual newtwork and subnet for the application gateway. 
resource "azurerm_virtual_network" "vnet" {
  name                = "gateway-poc-vnet"
  resource_group_name = azurerm_resource_group.poc_rg.name
  location            = azurerm_resource_group.poc_rg.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "gateway_subnet" {
  name                 = "gateway-subnet"
  resource_group_name  = azurerm_resource_group.poc_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

