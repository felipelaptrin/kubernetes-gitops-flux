locals {
  prefix = "kubernetes-bootstrap-flux"

  azs              = slice(data.aws_availability_zones.available.names, 0, var.vpc_azs_number)
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 4)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 8)]

  hosted_zone_id  = data.aws_route53_zone.this.zone_id
  hosted_zone_arn = data.aws_route53_zone.this.arn

  flux_bootstrap_path = "k8s/clusters/${var.environment}"

  acm_certificate_arn = module.ingress_acm_certificate.acm_certificate_arn

  k8s_cluster_name     = local.prefix // This local var is created only to avoid cyclical dependency between vpc and eks modules
  k8s_cluster_role     = module.eks.eks_managed_node_groups["general-purpose"].iam_role_name
  k8s_cluster_role_arn = module.eks.eks_managed_node_groups["general-purpose"].iam_role_arn
}
