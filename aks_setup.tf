############################################
# Minimal AKS cluster for learning
# Optimised for lowest cost, not for prod.
############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Set your subscription ID here, or export ARM_SUBSCRIPTION_ID before `terraform apply`
  # subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

############################################
# Variables you may want to tweak
############################################

variable "prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "learnaks"
}

variable "location" {
  description = "Azure region. Pick one close to you; some regions are cheaper than others."
  type        = string
  default     = "eastus"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = <<EOT
Cheap VM sizes suitable for AKS system nodes (need >=2 vCPU, >=4 GB RAM):
  - Standard_D2as_v7  : 2 vCPU / 8 GB  (AMD, cheapest allowed option in this subscription)
  - Standard_D2s_v7   : 2 vCPU / 8 GB  (Intel equivalent, slightly pricier)
EOT
  type        = string
  default     = "Standard_D2as_v7"
}

############################################
# Resources
############################################

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-dns"

  # Free tier control plane = $0. Paid "Standard" tier adds SLA + ~$0.10/hr.
  sku_tier = "Free"

  # Pick a supported version; leaving it null lets Azure pick the default.
  # kubernetes_version = "1.30.0"

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.node_vm_size

    # Smallest OS disk to save a few rupees on managed disk storage
    os_disk_size_gb = 32
    os_disk_type    = "Managed" # B-series often doesn't support "Ephemeral"

    # Do NOT enable autoscaling for a learning cluster; keep it predictable.
    auto_scaling_enabled = false

    # Put nodes in one zone to avoid cross-zone traffic charges
    # zones = ["1"]

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Azure CNI Overlay is cheaper than "Azure CNI" (no per-pod VNet IPs)
  # and is the modern replacement for kubenet.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    load_balancer_sku   = "standard"
    pod_cidr            = "10.244.0.0/16"
  }

 
  tags = {
    purpose = "learning"
    owner   = "me"
  }

  lifecycle {
    ignore_changes = [
      # kubernetes_version churn on plan when Azure bumps defaults
      kubernetes_version,
    ]
  }
}

############################################
# Outputs — handy after `terraform apply`
############################################

output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "get_credentials_command" {
  description = "Run this to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}
