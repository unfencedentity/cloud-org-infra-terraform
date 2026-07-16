resource "azurerm_resource_group" "core" {
  name     = var.resource_group_name
  location = var.location
}

data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network" "core" {
  name                = "vnet-dev-core-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "application" {
  name                 = "snet-app-dev-weu-001"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.core.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private_endpoint" {
  name                 = "snet-pe-dev-weu-001"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.core.name
  address_prefixes     = ["10.0.2.0/24"]

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_network_security_group" "application" {
  name                = "nsg-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
}

resource "azurerm_subnet_network_security_group_association" "application" {
  subnet_id                 = azurerm_subnet.application.id
  network_security_group_id = azurerm_network_security_group.application.id
}

resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "allow-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.core.name
  network_security_group_name = azurerm_network_security_group.application.name
}

resource "azurerm_public_ip" "application" {
  name                = "pip-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "application" {
  name                = "nic-app-dev-weu-001"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name

  ip_configuration {
    name                          = "ipconfig-app-dev-weu-001"
    subnet_id                     = azurerm_subnet.application.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.application.id
  }
}
