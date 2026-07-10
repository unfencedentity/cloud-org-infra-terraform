resource "azurerm_resource_group" "core" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "core" {
name = "vnet-dev-core-weu-001"
resource_group_name = azurerm_resource_group.core.name
}
