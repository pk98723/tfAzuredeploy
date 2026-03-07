provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "demo-cicd-rg"
  location = "East US"
}

resource "azurerm_container_registry" "acr" {
  name                = "democicdregistry"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}