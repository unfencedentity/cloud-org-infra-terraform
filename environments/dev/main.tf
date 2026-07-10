resource "azurerm_resource_group" "core" {
  name     = var.resource_group_name
  location = var.location
}

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
  network_security_group_name = azurerm_network_security_group.application.name
  resource_group_name         = azurerm_resource_group.core.name

}
