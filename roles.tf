############################################################
# Permisos que necesita el cluster para gestionar el LB
############################################################

data "azurerm_subscription" "current" {}

# — Network Contributor en el RG del cluster / vnet
resource "azurerm_role_assignment" "aks_network_rg" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id

  lifecycle { ignore_changes = [skip_service_principal_aad_check] }
}

# — Reader en toda la suscripción (recomendado por Microsoft)
resource "azurerm_role_assignment" "aks_reader_sub" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id

  lifecycle { ignore_changes = [skip_service_principal_aad_check] }
}

############################################################
# Rol personalizado “limitado” (opcional)
############################################################
resource "azurerm_role_definition" "aks_ingress_network_limited" {
  name        = "AKS-Ingress-Network-Limited"
  scope       = azurerm_resource_group.rg.id
  description = "Solo IPs públicas, LoadBalancers y NIC necesarios para el Ingress"

  permissions {
    actions = [
      "Microsoft.Network/publicIPAddresses/*",
      "Microsoft.Network/loadBalancers/*",
      "Microsoft.Network/networkInterfaces/*",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.Network/virtualNetworks/read",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.rg.id]

  lifecycle { prevent_destroy = true }
}

# (si quisieras asignarlo al cluster, descomenta)
# resource "azurerm_role_assignment" "aks_ingress_custom" {
#   scope              = azurerm_resource_group.rg.id
#   role_definition_id = azurerm_role_definition.aks_ingress_network_limited.role_definition_resource_id
#   principal_id       = azurerm_kubernetes_cluster.aks.identity[0].principal_id
# }
