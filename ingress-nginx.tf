########################################
# Helm – NGINX Ingress Controller
########################################
provider "helm" {
  alias = "aks"
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks.kube_admin_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].cluster_ca_certificate)
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_key)
  }
}

resource "helm_release" "ingress_nginx" {
  provider         = helm.aks
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.1"

  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 900

  set = [
    {
      # IP que llevará SIEMPRE el LoadBalancer
      name  = "controller.service.loadBalancerIP"
      value = azurerm_public_ip.ingress_ip.ip_address      # ← usa ingress_ip
    },
    {
      # Asegura que el LB se cree en el RG del cluster
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-resource-group"
      value = azurerm_resource_group.rg.name
    }
  ]

  depends_on = [
    azurerm_public_ip.ingress_ip,                           # ← idem
    azurerm_kubernetes_cluster.aks
  ]
}
