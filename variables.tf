variable "name-prefix" {
  description = "Prefix for the name of the resources"
  type        = string
  default     = "livekit-agent-azure" 
}

variable "region" {
  description = "The region in which the resources will be deployed"
  type        = string
  default     = "Sweden Central" 
}

variable "ai-sku" {
  description = "The pricing tier for the Speech Cognitive Service"
  type        = string
  default     = "S0" 
}

variable "vm-sku" {
  description = "The size of the Virtual Machine"
  type        = string
  default     = "Standard_B4ms" 
}

variable "aks-node-count" {
  description = "The number of nodes in the AKS cluster"
  type        = number
  default     = 2  
}

variable "aks-price-tier" {
  description = "The pricing tier for the AKS cluster"
  type        = string
  default     = "Standard"
}

variable "vnet-ip" {
  description = "The IP range for the VNET"
  type        = string
  default     = "10.26.0.0"
}

variable "vnet-mask" {
  description = "The subnet mask for the VNET"
  type        = string
  default     = "/16"
}

variable "subnet-mask" {
  description = "The subnet mask for the AKS cluster - nodes and pods"
  type        = string
  default     = "/20"
}
