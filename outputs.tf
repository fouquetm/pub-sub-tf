output "api_fqdn" {
  value = azurerm_container_app.api.ingress[0].fqdn
}

output "api_get_product_list_url" {
  value = "${azurerm_container_app.api.ingress[0].fqdn}/api/Product/productlist"
}

