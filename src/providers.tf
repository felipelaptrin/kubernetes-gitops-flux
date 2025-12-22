provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      CreatedBy  = "Terraform"
      Repository = "https://github.com/felipelaptrin/kubernetes-gitops-flux"
    }
  }
}

provider "flux" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
  git = {
    url = "https://github.com/felipelaptrin/kubernetes-gitops-flux"
    http = {
      username = "git" # This can be any string when using a personal access token
      password = var.github_token
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "github" {
  token = var.github_token
}
