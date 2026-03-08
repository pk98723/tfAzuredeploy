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
    tls = {
      source  = "hashicorp/tls"
      version = "~>4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -------------------------
# Resource Group (check existing)
# -------------------------
data "azurerm_resource_group" "existing" {
  name = "demo-cicd-rg"
}

resource "azurerm_resource_group" "rg" {
  count    = data.azurerm_resource_group.existing != null ? 0 : 1
  name     = "demo-cicd-rg"
  location = "East US"

  lifecycle {
    prevent_destroy = true
  }
}

# -------------------------
# Container Registry (ACR)
# -------------------------
data "azurerm_container_registry" "existing" {
  name                = "democicdregistry"
  resource_group_name = "demo-cicd-rg"
}

resource "azurerm_container_registry" "acr" {
  count               = data.azurerm_container_registry.existing != null ? 0 : 1
  name                = "democicdregistry"
  resource_group_name = coalesce(data.azurerm_resource_group.existing.name, azurerm_resource_group.rg[0].name)
  location            = "East US"
  sku                 = "Basic"
  admin_enabled       = true
}

# -------------------------
# Log Analytics Workspace
# -------------------------
data "azurerm_log_analytics_workspace" "existing" {
  name                = "demo-aks-logs"
  resource_group_name = "demo-cicd-rg"
}

resource "azurerm_log_analytics_workspace" "log" {
  count               = data.azurerm_log_analytics_workspace.existing != null ? 0 : 1
  name                = "demo-aks-logs"
  location            = "East US"
  resource_group_name = coalesce(data.azurerm_resource_group.existing.name, azurerm_resource_group.rg[0].name)
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# -------------------------
# AKS Cluster
# -------------------------
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

data "azurerm_kubernetes_cluster" "existing" {
  name                = "demo-aks-cluster"
  resource_group_name = "demo-cicd-rg"
}

resource "azurerm_kubernetes_cluster" "aks" {
  count               = data.azurerm_kubernetes_cluster.existing != null ? 0 : 1
  name                = "demo-aks-cluster"
  location            = "East US"
  resource_group_name = coalesce(data.azurerm_resource_group.existing.name, azurerm_resource_group.rg[0].name)
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
    log_analytics_workspace_id = coalesce(data.azurerm_log_analytics_workspace.existing.id, azurerm_log_analytics_workspace.log[0].id)
  }

  tags = {
    environment = "demo"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -------------------------
# Allow AKS to Pull from ACR
# -------------------------
resource "azurerm_role_assignment" "acr_pull" {
  depends_on = [azurerm_kubernetes_cluster.aks, azurerm_container_registry.acr]

  principal_id         = azurerm_kubernetes_cluster.aks[0].kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr[0].id
}

# -------------------------
# Outputs
# -------------------------
output "acr_login_server" {
  value = azurerm_container_registry.acr[0].login_server
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks[0].name
}