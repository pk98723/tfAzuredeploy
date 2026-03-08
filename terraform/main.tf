terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "cicdtfstate12345"
    container_name       = "tfstate"
    key                  = "aks-cicd.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

##########################################################
# Resource Group
##########################################################
data "azurerm_resource_group" "existing" {
  name = "demo-cicd-rg"
}

resource "azurerm_resource_group" "rg" {
  count    = length(data.azurerm_resource_group.existing.*.id) == 0 ? 1 : 0
  name     = "demo-cicd-rg"
  location = "East US"

  lifecycle {
    prevent_destroy = true
  }
}

##########################################################
# Container Registry (ACR)
##########################################################
data "azurerm_container_registry" "existing" {
  name                = "democicdregistry"
  resource_group_name = "demo-cicd-rg"
}

resource "azurerm_container_registry" "acr" {
  count               = length(data.azurerm_container_registry.existing.*.id) == 0 ? 1 : 0
  name                = "democicdregistry"
  resource_group_name = coalesce(azurerm_resource_group.rg[0].name, "demo-cicd-rg")
  location            = coalesce(azurerm_resource_group.rg[0].location, "East US")
  sku                 = "Basic"
  admin_enabled       = true
}

##########################################################
# Log Analytics Workspace
##########################################################
data "azurerm_log_analytics_workspace" "existing" {
  name                = "demo-aks-logs"
  resource_group_name = "demo-cicd-rg"
}

resource "azurerm_log_analytics_workspace" "log" {
  count               = length(data.azurerm_log_analytics_workspace.existing.*.id) == 0 ? 1 : 0
  name                = "demo-aks-logs"
  location            = coalesce(azurerm_resource_group.rg[0].location, "East US")
  resource_group_name = coalesce(azurerm_resource_group.rg[0].name, "demo-cicd-rg")
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

##########################################################
# AKS Cluster
##########################################################
data "azurerm_kubernetes_cluster" "existing" {
  name                = "demo-aks-cluster"
  resource_group_name = "demo-cicd-rg"
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_kubernetes_cluster" "aks" {
  count               = length(data.azurerm_kubernetes_cluster.existing.*.id) == 0 ? 1 : 0
  name                = "demo-aks-cluster"
  location            = coalesce(azurerm_resource_group.rg[0].location, "East US")
  resource_group_name = coalesce(azurerm_resource_group.rg[0].name, "demo-cicd-rg")
  dns_prefix          = "demoaks"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }

  linux_profile {
    admin_username = "azureuser"
    ssh_key {
      key_data = tls_private_key.ssh_key.public_key_openssh
    }
  }

  oms_agent {
    log_analytics_workspace_id = coalesce(azurerm_log_analytics_workspace.log[0].id, "")
  }

  tags = {
    environment = "demo"
  }

  lifecycle {
    prevent_destroy = true
  }
}

##########################################################
# AKS Pull from ACR
##########################################################
resource "azurerm_role_assignment" "acr_pull" {
  count                = length(data.azurerm_container_registry.existing.*.id) == 0 ? 0 : 1
  principal_id         = azurerm_kubernetes_cluster.aks[0].kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = coalesce(azurerm_container_registry.acr[0].id, data.azurerm_container_registry.existing.id)
}

##########################################################
# Outputs
##########################################################
output "acr_login_server" {
  value = coalesce(azurerm_container_registry.acr[0].login_server, data.azurerm_container_registry.existing.login_server)
}

output "aks_name" {
  value = coalesce(azurerm_kubernetes_cluster.aks[0].name, data.azurerm_kubernetes_cluster.existing.name)
}