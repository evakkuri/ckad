terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.95.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.47.0"
    }
  }
}

provider "azurerm" {
  tenant_id           = "brainflight.fi"
  subscription_id     = "8131544b-6c32-4d20-bda1-746a58221883"
  storage_use_azuread = true
  features {}
}

provider "azuread" {
  tenant_id = "brainflight.fi"
}

resource "azurerm_resource_group" "ckad" {
  name     = "ckad"
  location = "swedencentral"
}

resource "azuread_group" "ckad_admin" {
  display_name     = "ckad-admin"
  security_enabled = true
  members = [
    "4e774570-89ea-4c35-ba62-2a484d8b4b48"
  ]
}

resource "azurerm_virtual_network" "ckad" {
  name                = "ckad-vnet"
  resource_group_name = azurerm_resource_group.ckad.name
  location            = azurerm_resource_group.ckad.location
  address_space = [
    "10.0.0.0/16"
  ]
}

resource "azurerm_subnet" "ckad_aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = azurerm_resource_group.ckad.name
  virtual_network_name = azurerm_virtual_network.ckad.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "ckad_aks_defaultpool_pods" {
  name                 = "ckad-aks-defaultpool-pods"
  resource_group_name  = azurerm_resource_group.ckad.name
  virtual_network_name = azurerm_virtual_network.ckad.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "aks-delegation"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      name    = "Microsoft.ContainerService/managedClusters"
    }
  }
}

resource "azurerm_kubernetes_cluster" "ckad" {
  name                      = "ckad"
  resource_group_name       = azurerm_resource_group.ckad.name
  location                  = azurerm_resource_group.ckad.location
  node_resource_group       = "ckad-node-rg"
  workload_identity_enabled = true
  dns_prefix                = "ckad"
  local_account_disabled    = true
  oidc_issuer_enabled       = true
  kubernetes_version        = "1.28"

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.2.0.0/24"
    dns_service_ip = "10.2.0.10"
  }

  api_server_access_profile {
    authorized_ip_ranges = [
      "194.34.132.57/32",
      "194.34.132.59/32"
    ]
  }

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
    admin_group_object_ids = [
      azuread_group.ckad_admin.object_id
    ]
  }

  default_node_pool {
    name           = "agentpool"
    vm_size        = "Standard_DS2_v2"
    node_count     = 2
    vnet_subnet_id = azurerm_subnet.ckad_aks_nodes.id
    pod_subnet_id  = azurerm_subnet.ckad_aks_defaultpool_pods.id
  }
}

resource "azurerm_role_assignment" "ckad_admin" {
  principal_id         = azuread_group.ckad_admin.object_id
  scope                = azurerm_kubernetes_cluster.ckad.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
}
