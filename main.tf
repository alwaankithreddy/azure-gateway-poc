# 1. Terraform & Provider Configuration
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

# 2. Resource Group
resource "azurerm_resource_group" "poc_rg" {
  name     = "Gateway-POC-RG"
  location = "East US"
}

# 3. Networking Layer
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

resource "azurerm_subnet" "backend_subnet" {
  name                 = "backend-subnet"
  resource_group_name  = azurerm_resource_group.poc_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "gateway_pip" {
  name                = "gateway-pip"
  resource_group_name = azurerm_resource_group.poc_rg.name
  location            = azurerm_resource_group.poc_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 4. Application Gateway
resource "azurerm_application_gateway" "main_gateway" {
  name                = "app-gateway-poc"
  resource_group_name = azurerm_resource_group.poc_rg.name
  location            = azurerm_resource_group.poc_rg.location

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
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

  backend_address_pool { name = "images-pool" }
  backend_address_pool { name = "video-pool" }

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

  request_routing_rule {
    name               = "path-rule"
    rule_type          = "PathBasedRouting"
    http_listener_name = "listener"
    url_path_map_name  = "routing-map"
    priority           = 1
  }

  url_path_map {
    name                               = "routing-map"
    default_backend_address_pool_name  = "images-pool"
    default_backend_http_settings_name = "http-setting"

    path_rule {
      name                       = "video-path"
      paths                      = ["/video/*"]
      backend_address_pool_name  = "video-pool"
      backend_http_settings_name = "http-setting"
    }
  }
}

# 5. Network Interfaces (NICs)
resource "azurerm_network_interface" "nic_images" {
  name                = "nic-images"
  location            = azurerm_resource_group.poc_rg.location
  resource_group_name = azurerm_resource_group.poc_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.backend_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "nic_video" {
  name                = "nic-video"
  location            = azurerm_resource_group.poc_rg.location
  resource_group_name = azurerm_resource_group.poc_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.backend_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 6. Backend Pool Associations
resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "images_assoc" {
  network_interface_id    = azurerm_network_interface.nic_images.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = tolist(azurerm_application_gateway.main_gateway.backend_address_pool).0.id
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "video_assoc" {
  network_interface_id    = azurerm_network_interface.nic_video.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = tolist(azurerm_application_gateway.main_gateway.backend_address_pool).1.id
}

# 7. Virtual Machines (D-Series for Reliability)
resource "azurerm_linux_virtual_machine" "vm_images" {
  name                = "vm-images"
  resource_group_name = azurerm_resource_group.poc_rg.name
  location            = azurerm_resource_group.poc_rg.location
  size                = "Standard_D2s_v3"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic_images.id]

  admin_password                  = "P@ssw0rd1234!"
  disable_password_authentication = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo apt-get update && sudo apt-get install -y nginx
              sudo mkdir -p /var/www/html/images
              echo "<h1>Welcome to the IMAGES Server</h1>" > /var/www/html/images/index.html
              sudo systemctl restart nginx
              EOF
  )
}

resource "azurerm_linux_virtual_machine" "vm_video" {
  name                = "vm-video"
  resource_group_name = azurerm_resource_group.poc_rg.name
  location            = azurerm_resource_group.poc_rg.location
  size                = "Standard_D2s_v3"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic_video.id]

  admin_password                  = "P@ssw0rd1234!"
  disable_password_authentication = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo apt-get update && sudo apt-get install -y nginx
              sudo mkdir -p /var/www/html/video
              echo "<h1>Welcome to the VIDEO Server</h1>" > /var/www/html/video/index.html
              sudo systemctl restart nginx
              EOF
  )
}
