provider "azurerm" {
  features {}
}

# Create Resource Groups
resource "azurerm_resource_group" "main-rg" {
  name     = var.name-prefix
  location = var.region
}

# Create Cognitive Services account for Speech
resource "azurerm_cognitive_account" "speech" {
  name                = "${var.name-prefix}-speech-service"
  location            = var.region
  resource_group_name = azurerm_resource_group.main-rg.name
  kind                = "SpeechServices"  
  sku_name            = var.ai-sku             
}

resource "azurerm_cognitive_account" "openai" {
  name                = "${var.name-prefix}-openai-service"
  location            = var.region
  resource_group_name = azurerm_resource_group.main-rg.name
  kind                = "OpenAI"
  sku_name            = var.ai-sku  
}

# Deploy GPT-4o Model
resource "azurerm_cognitive_deployment" "openai-model" {
  name                 = "${var.name-prefix}-openai-model"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 10 # ~10k token per minute
  }
}

# Create Virtual Networks
resource "azurerm_virtual_network" "main-vnet" {
  name                = "${var.name-prefix}-vnet"
  location            = var.region
  resource_group_name = azurerm_resource_group.main-rg.name
  address_space       = ["${var.vnet-ip}${var.vnet-mask}"] 
}

# Create Subnets
resource "azurerm_subnet" "main-subnet" {
  name                     = "${var.name-prefix}-subnet"
  resource_group_name      = azurerm_resource_group.main-rg.name
  virtual_network_name     = "${var.name-prefix}-vnet"
  address_prefixes         = ["${var.vnet-ip}${var.subnet-mask}"] 
}

# Create AKS Clusters
resource "azurerm_kubernetes_cluster" "aks-cluster" {
    name                = "${var.name-prefix}-k8s"
    location            = var.region
    resource_group_name = azurerm_resource_group.main-rg.name
    dns_prefix          = var.name-prefix
    sku_tier            = var.aks-price-tier

    default_node_pool {
        name           = "default"
        node_count     = var.aks-node-count
        vm_size        = var.vm-sku
        vnet_subnet_id = azurerm_subnet.main-subnet.id

        # these settings seems to be defults that constantly bother me during applys...
        upgrade_settings {
            drain_timeout_in_minutes      = 0
            max_surge                     = "10%"
            node_soak_duration_in_minutes = 0
        }
    }

    identity {
        type = "SystemAssigned"
    }

    network_profile {
        network_plugin = "azure"
        //dns_service_ip = "10.26.2.10"
        //service_cidr   = "10.26.2.0/24"
        //docker_bridge_cidr = "172.18.0.1/16"
        //pod_cidr       = "10.26.3.0/24"
    }
}
