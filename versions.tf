terraform {
  required_version = ">= 0.13.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.5"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
    # https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.9.4"
    }

    external = {
      source  = "hashicorp/external"
      version = ">= 2.0.0"
    }
  }
}
