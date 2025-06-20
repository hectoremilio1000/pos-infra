########################################
# IP pública estática para Ingress
########################################
resource "azurerm_public_ip" "ingress_ip" {
  name                = "pos-ingress-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  allocation_method = "Static"
  sku               = "Standard"

  tags = {
    Component   = "Ingress"
    Environment = "Prod"
  }
}
