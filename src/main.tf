##############################
##### NETWORKING
##############################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.5.1"

  name = local.prefix
  cidr = var.vpc_cidr

  azs              = local.azs
  private_subnets  = local.private_subnets
  public_subnets   = local.public_subnets
  database_subnets = local.database_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  # VPC Requirements: https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"       = 1
    "kubernetes.io/cluster/${local.prefix}" = "owned"
    "karpenter.sh/discovery"                = local.k8s_cluster_name
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                = 1
    "kubernetes.io/cluster/${local.prefix}" = "owned"
  }
}

##############################
##### DATABASE
##############################
# module "sg_authentik_db" {
#   source  = "terraform-aws-modules/security-group/aws"
#   version = "5.3.0"

#   name   = "authentik-rds"
#   vpc_id = module.vpc.vpc_id

#   ingress_with_cidr_blocks = [
#     {
#       from_port   = 5432
#       to_port     = 5432
#       protocol    = "tcp"
#       description = "PostgreSQL access from within VPC"
#       cidr_blocks = module.vpc.vpc_cidr_block
#     },
#   ]
# }

# module "db_authentik" {
#   source  = "terraform-aws-modules/rds/aws"
#   version = "6.13.0"

#   identifier = "authentik"

#   engine                   = "postgres"
#   engine_version           = "17"
#   engine_lifecycle_support = "open-source-rds-extended-support-disabled"
#   family                   = "postgres17"
#   major_engine_version     = "17.5"
#   instance_class           = "db.t3.micro"

#   allocated_storage     = 20
#   max_allocated_storage = 100

#   db_name  = "authentik"
#   username = "authentik"
#   port     = 5432

#   manage_master_user_password_rotation              = true
#   master_user_password_rotate_immediately           = false
#   master_user_password_rotation_schedule_expression = "rate(15 days)"

#   multi_az               = true
#   db_subnet_group_name   = module.vpc.database_subnet_group
#   vpc_security_group_ids = [module.sg_authentik_db.security_group_id]

#   skip_final_snapshot = true
#   deletion_protection = false
# }

##############################
##### KUBERNETES
##############################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "v21.10.1"

  name               = local.k8s_cluster_name
  kubernetes_version = var.k8s_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.k8s_cluster_name
  }

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = false

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      addon_version = var.k8s_addons_versions["eks-pod-identity-agent"]
    }
  }

  # Best way to grant users access to Kubernetes API: https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
  access_entries = {
    sso_admins = {
      principal_arn = "arn:aws:iam::937168356724:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_35d503478c27a34c"
      policy_associations = {
        sso_admins = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Using EKS-Optimized Images: https://aws.amazon.com/blogs/containers/amazon-eks-optimized-amazon-linux-2023-amis-now-available/
  eks_managed_node_groups = {
    general-purpose = {
      ami_type = "AL2023_ARM_64_STANDARD"
      instance_types = [
        "m6g.large"
      ]
      min_size     = 2
      max_size     = 2
      desired_size = 2
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }
}

module "ingress_acm_certificate" {
  source  = "terraform-aws-modules/acm/aws"
  version = "6.2.0"

  domain_name = var.domain
  zone_id     = local.hosted_zone_id

  validation_method = "DNS"
  subject_alternative_names = [
    "*.${var.domain}",
  ]
  wait_for_validation = true
}
