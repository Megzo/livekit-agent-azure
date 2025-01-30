output "speech_key" {
  value     = azurerm_cognitive_account.speech.primary_access_key
  sensitive = true
}

output "speech_endpoint" {
  value = azurerm_cognitive_account.speech.endpoint
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "openai_key" {
  value     = azurerm_cognitive_account.openai.primary_access_key
  sensitive = true
}

output "kubeconfig" {
  value     = azurerm_kubernetes_cluster.aks-cluster.kube_config_raw
  sensitive = true
}
