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

# This creates the Public IP address for your Gateway
resource "azurerm_public_ip" "gateway_pip" {
  name                = "gateway-pip"
  resource_group_name = azurerm_resource_group.poc_rg.name
  location            = azurerm_resource_group.poc_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# This is the "Brain" (The Gateway itself)
resource "azurerm_application_gateway" "main_gateway" {
  name                = "app-gateway-poc"
  resource_group_name = azurerm_resource_group.poc_rg.name
  location            = azurerm_resource_group.poc_rg.location

    # this block to fix the TLS error
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101" # This is a modern, supported version
  }

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-config"
    subnet_id = azurerm_subnet.gateway_subnet.id
  }

  frontend_port {
    name = "frontend-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.gateway_pip.id
  }

  # --- BACKEND POOLS (The "Groups" of servers) ---
  backend_address_pool {
    name = "images-pool"
  }

  backend_address_pool {
    name = "video-pool"
  }

  backend_http_settings {
    name                  = "http-setting"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "frontend-port"
    protocol                       = "Http"
  }

  # --- THE ROUTING RULE (The "Path Logic") ---
  request_routing_rule {
    name               = "path-rule"
    rule_type          = "PathBasedRouting"
    http_listener_name = "listener"
    url_path_map_name  = "routing-map"
    priority           = 1
  }

  url_path_map {
    name                               = "routing-map"
    default_backend_address_pool_name  = "images-pool" # Default if no path matches
    default_backend_http_settings_name = "http-setting"

    path_rule {
      name                       = "video-path"
      paths                      = ["/video/*"]
      backend_address_pool_name  = "video-pool"
      backend_http_settings_name = "http-setting"
    }
  }
}
