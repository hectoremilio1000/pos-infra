########################################
# IP pública estática para el Ingress
########################################
resource "azurerm_public_ip" "ingress_ip" {
  name                = "pos-ingress-ip"                 # ← sigue igual
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  allocation_method   = "Static"                         # estática ✔
  sku                 = "Standard"                       # Standard ✔

  tags = {
    Component   = "Ingress"
    Environment = "Prod"
  }
}
