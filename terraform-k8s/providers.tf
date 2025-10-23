terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25"
    }
  }
}

provider "kubernetes" {
  config_path = "/app/.kube/config"
}
