provider "authentik" {
  url   = "https://authentik.${var.domain}"
  token = jsondecode(data.aws_secretsmanager_secret_version.authentik_token.secret_string)["token"]
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      CreatedBy  = "Terraform"
      Repository = "https://github.com/felipelaptrin/kubernetes-gitops-flux"
    }
  }
}
