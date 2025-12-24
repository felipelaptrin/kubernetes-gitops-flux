variable "environment" {
  description = "Environment to deploy. It uses this name as the path of the Kubernetes manifests"
  type        = string

  validation {
    condition     = contains(["dev"], var.environment)
    error_message = "Valid values for var: environment are (dev)."
  }
}

variable "github_token" {
  description = "GitHub PAT"
  type        = string
}

variable "repository_name" {
  description = "Repository name."
  type        = string
}

# ##############################
# ##### DOMAIN
# ##############################
variable "domain" {
  description = "Route53 Domain - Hosted Zone - to be used. This resource should be created manually and will be just used in Terraform code as a data source."
  type        = string
}

##############################
##### AWS RELATED
##############################
variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# ##############################
# ##### NETWORKING
# ##############################
variable "vpc_azs_number" {
  description = "Number of AZs to use when deploying the VPC"
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR of the VPC"
  type        = string
}

# ##############################
# ##### KUBERNETES RELATED
# ##############################
variable "k8s_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "k8s_addons_versions" {
  description = "EKS addons versions. Check the available versions on https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html"
  type = object({
    eks-pod-identity-agent = string
    aws-ebs-csi-driver     = string
  })
  default = {
    eks-pod-identity-agent = "v1.3.10-eksbuild.2"
    aws-ebs-csi-driver     = "v1.53.0-eksbuild.1"
  }
}

# ##############################
# ##### KUBERNETES BOOTSTRAP RELATED
# ##############################
variable "flux_version" {
  description = "Flux version to bootstrap with Terraform"
  type        = string
  default     = "v2.7.5"
}


variable "secret_recovery_window" {
  description = "Number of days that AWS Secrets Manager waits before it can delete the secret"
  type        = number
}
