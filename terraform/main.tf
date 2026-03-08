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

resource "azurerm_resource_group" "rg" {
  name     = "demo-cicd-rg"
  location = "East US"

  lifecycle {
    prevent_destroy = true
  }

  # Only create if the data source does not exist
  count = data.azurerm_resource_group.existing != null ? 0 : 1
}


resource "azurerm_resource_group" "rg" {
  name     = "demo-cicd-rg"
  location = "East US"
}

data "azurerm_container_registry" "existing" {
  name                = "democicdregistry"
  resource_group_name = "demo-cicd-rg"
}

data "azurerm_log_analytics_workspace" "existing" {
  name                = "demo-aks-logs"
  resource_group_name = "demo-cicd-rg"
}

data "azurerm_kubernetes_cluster" "existing" {
  name                = "demo-aks-cluster"
  resource_group_name = "demo-cicd-rg"
}

resource "azurerm_container_registry" "acr" {
  name                = "democicdregistry"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true

  count = data.azurerm_container_registry.existing != null ? 0 : 1
}


# Log Analytics (AKS Monitoring)


resource "azurerm_log_analytics_workspace" "log" {
  name                = "demo-aks-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  count = data.azurerm_log_analytics_workspace.existing != null ? 0 : 1
}

#################################
# AKS Cluster
#################################

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "demo-aks-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
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
    log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id
  }

  tags = {
    environment = "demo"
  }

  lifecycle {
    prevent_destroy = true
  }

  count = data.azurerm_kubernetes_cluster.existing != null ? 0 : 1

}

#################################
# Allow AKS to Pull from ACR
#################################

resource "azurerm_role_assignment" "acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}

#################################
# Outputs
#################################

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}