terraform {
  backend "azurerm" {
    resource_group_name  = "myTFResourceGroup"
    storage_account_name = "posinfrastate"   # ← el que creaste
    container_name       = "tfstate"
    key                  = "posinfra.terraform.tfstate"
  }
}

########################################
# Bloque terraform + providers
########################################
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.98" # ← cualquier 3.x reciente ≥ 3.50
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

########################################
# Provider Azure
########################################
provider "azurerm" {
  features {}
}

########################################
# Recurso base: Resource Group
########################################
resource "azurerm_resource_group" "rg" {
  name     = "myTFResourceGroup"
  location = "westus2"

  # Etiquetas (puedes cambiarlas cuando quieras)
  tags = {
    Environment = "Terraform Getting Started"
    Team        = "DevOps"
  }
}

########################################
# Random · sufijo único para nombres
########################################
resource "random_id" "acr_suffix" {
  byte_length = 2
}

########################################
# Azure Container Registry (ACR)
########################################
resource "azurerm_container_registry" "acr" {
  name                = "posacr${random_id.acr_suffix.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku           = "Basic"
  admin_enabled = true
}

########################################
# Virtual Network
########################################
resource "azurerm_virtual_network" "vnet" {
  name                = "myTFVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}


######################################### segunda parte #############
########################################
# SUBNET app dentro de la VNet
########################################
resource "azurerm_subnet" "app" {
  name                 = "app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = ["10.0.1.0/24"] # primera manzana del barrio
}

########################################
# Network Security Group (firewall L4)
########################################
resource "azurerm_network_security_group" "app_nsg" {
  name                = "app-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Regla: permite HTTP entrante
  security_rule {
    name                       = "allow_http_in"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Regla: permite HTTPS entrante
  security_rule {
    name                       = "allow_https_in"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

########################################
# Asociación NSG ↔ Subnet
########################################
resource "azurerm_subnet_network_security_group_association" "app_assoc" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
}


########################
# 1. Public IP para NAT
########################
resource "azurerm_public_ip" "nat_eip" {
  name                = "nat-eip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  allocation_method = "Static"
  sku               = "Standard"
}

########################
# 2. NAT Gateway
########################
resource "azurerm_nat_gateway" "nat_gw" {
  name                = "nat-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard"
}

# Asociación NAT ↔ IP pública  (solo necesario en providers antiguos)
resource "azurerm_nat_gateway_public_ip_association" "nat_eip_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.nat_gw.id
  public_ip_address_id = azurerm_public_ip.nat_eip.id
}

########################
# 3. Asociación NAT ↔ Subnet
########################
resource "azurerm_subnet_nat_gateway_association" "app_nat" {
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.nat_gw.id
}

########################################
# Subnet DB (delegada a PostgreSQL)
########################################
resource "azurerm_subnet" "db" {
  name                 = "db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = ["10.0.2.0/24"]

  delegation {
    name = "pgsql_flexible"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# ──────────────────────────────────────────────────────────────
#   PRIVATE DNS ZONE para PostgreSQL Flexible Server
# ──────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "pgsql" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "pgsql_link" {
  name                  = "vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.pgsql.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

########################################
# PostgreSQL Flexible Server (SKU B1ms)
########################################
resource "random_password" "pg_admin_pw" {
  length  = 20
  special = true
}

resource "azurerm_postgresql_flexible_server" "db" {
  name                   = "pospg-${random_id.acr_suffix.hex}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  administrator_login    = "pgadmin"
  administrator_password = random_password.pg_admin_pw.result
  zone                   = "1"

  delegated_subnet_id           = azurerm_subnet.db.id
  private_dns_zone_id           = azurerm_private_dns_zone.pgsql.id
  public_network_access_enabled = false # 👈 solo dentro de la VNet

  sku_name   = "B_Standard_B1ms" # 1 vCPU / 2 GB RAM (≈ 15 USD mes)
  version    = "16"              # PostgreSQL 16
  storage_mb = 32768             # 32 GB (mínimo)

  maintenance_window {
    day_of_week  = 0 # domingo
    start_hour   = 3 # 03 h UTC
    start_minute = 0
  }

  backup_retention_days = 7 # PITR 7 días
  tags = {
    env = "dev"
  }
}

########################################
# Salida con la cadena de conexión
########################################
output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.db.fqdn
}

# ------------ SUBNET para AKS ------------
resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

# (fuera del recurso) ── identidad de tu tenant
data "azurerm_client_config" "current" {}

# ───────────── CLUSTER AKS ─────────────
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "pos-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "posaks"

  identity { type = "SystemAssigned" }

  default_node_pool {
    name                = "sys"
    vm_size             = "Standard_B2s"
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 2
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    dns_service_ip = "10.100.0.10"
    service_cidr   = "10.100.0.0/16"

  }

  # ↪ antes dentro de addon_profile → ahora bloque raíz
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  }




  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true # habilitar RBAC nativo de Azure
    managed            = true # habilitar integración AAD administrada
    # admin_group_object_ids = ["<ID-de-grupo-AD-opcional>"]  # grupo admin de AKS (opcional)
  }





  oidc_issuer_enabled = true
  tags                = { env = "dev" }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.pgsql_link]
}


# ------------ LOG ANALYTICS (antes del cluster) ------------
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "pos-logs"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


# ------------ ACR → AKS pull permiso ------------
resource "azurerm_role_assignment" "aks_pull_acr" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
