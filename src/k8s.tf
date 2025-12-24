##############################
##### BOOTSTRAP FLUX
##############################
resource "kubernetes_namespace_v1" "flux" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      # The labels below are to avoid drift with Flux
      "app.kubernetes.io/instance"            = "flux-system"
      "app.kubernetes.io/part-of"             = "flux"
      "app.kubernetes.io/version"             = var.flux_version
      "kustomize.toolkit.fluxcd.io/name"      = "flux-system"
      "kustomize.toolkit.fluxcd.io/namespace" = "flux-system"
    }
    name = "flux-system"
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on = [
    kubernetes_config_map_v1.cluster_vars,
    kubernetes_namespace_v1.flux,
    kubernetes_namespace_v1.external_dns,
    kubernetes_namespace_v1.karpenter,
    kubernetes_namespace_v1.authentik,
    module.karpenter,
  ]

  path    = local.flux_bootstrap_path
  version = var.flux_version
}

resource "github_repository_file" "flux_bootstrap_crds" {
  repository          = var.repository_name
  branch              = "main"
  file                = "${local.flux_bootstrap_path}/crds.yaml"
  content             = <<-YAML
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: crds
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./k8s/crds/${var.environment}
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
YAML
  commit_message      = "bootstrap flux by installing Kustomize CR to deploy CRDs"
  overwrite_on_create = true
}

resource "github_repository_file" "flux_bootstrap_karpenter" {
  repository          = var.repository_name
  branch              = "main"
  file                = "${local.flux_bootstrap_path}/karpenter.yaml"
  content             = <<-YAML
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: karpenter
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./k8s/addons/${var.environment}/karpenter
  prune: true
  dependsOn:
    - name: crds
  sourceRef:
    kind: GitRepository
    name: flux-system
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars-terraform
YAML
  commit_message      = "bootstrap flux by installing Kustomize CR to deploy Karpenter"
  overwrite_on_create = true
}

resource "github_repository_file" "flux_bootstrap_addons" {
  repository          = var.repository_name
  branch              = "main"
  file                = "${local.flux_bootstrap_path}/addons.yaml"
  content             = <<-YAML
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: addons
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./k8s/addons/${var.environment}
  prune: true
  dependsOn:
    - name: crds
    - name: karpenter
  sourceRef:
    kind: GitRepository
    name: flux-system
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars-terraform
YAML
  commit_message      = "bootstrap flux by installing Kustomize CR to deploy addons"
  overwrite_on_create = true
}

resource "kubernetes_config_map_v1" "cluster_vars" {
  depends_on = [kubernetes_namespace_v1.flux]
  immutable  = true

  metadata {
    name      = "cluster-vars-terraform"
    namespace = "flux-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "TF_AWS_REGION"                   = var.aws_region
    "TF_ACM_CERT_ARN"                 = local.acm_certificate_arn
    "TF_HEADLAMP_HOSTNAME"            = "headlamp.${var.domain}"
    "TF_AUTHENTIK_HOSTNAME"           = "authentik.${var.domain}"
    "TF_CLUSTER_NAME"                 = local.k8s_cluster_name
    "TF_K8S_NODE_ROLE_NAME"           = local.k8s_cluster_role
    "TF_AUTHENTIK_DB_SECRET_ARN"      = module.db_authentik.db_instance_master_user_secret_arn
    "TF_AUTHENTIK_SECRET_MANAGER_ARN" = aws_secretsmanager_secret.authentik_secret.arn
    "TF_HEADLAMP_SECRET_MANAGER_ARN"  = aws_secretsmanager_secret.headlamp_secret.arn
  }
}

##############################
##### AWS EBS CSI DRIVER
##############################
# Reference: https://davegallant.ca/blog/amazon-ebs-csi-driver-terraform/
resource "aws_iam_role" "ebs_csi_driver" {
  name               = "ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json
}

data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.k8s_addons_versions["aws-ebs-csi-driver"]
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}
##############################
##### GATEWAY API
##############################
resource "kubernetes_config_map_v1" "gateway_api" {
  metadata {
    name      = "gateway-api-values-terraform"
    namespace = "flux-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    ACM_CERT_ARN = local.acm_certificate_arn
    BASE_DOMAIN  = var.domain
  }
}

##############################
##### EXTERNAL-DNS
##############################
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "v2.6.0"

  name                          = "external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [local.hosted_zone_arn]
  associations = {
    external-dns = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-dns"
      service_account = "external-dns"
    }
  }
}

resource "kubernetes_namespace_v1" "external_dns" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    name = "external-dns"
  }
}

resource "kubernetes_config_map_v1" "external_dns" {
  depends_on = [kubernetes_namespace_v1.external_dns]
  immutable  = true

  metadata {
    name      = "external-dns-values-terraform"
    namespace = "external-dns"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "values.yaml" = yamlencode({
      env = [{
        name : "AWS_DEFAULT_REGION"
        value : var.aws_region
      }]
      domainFilters = [
        var.domain
      ]
    })
  }
}
##############################
##### EXTERNAL SECRETS
##############################
module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "v2.6.0"

  name = "external-secrets"

  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:${var.aws_region}:*:*:*"]

  associations = {
    external-secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

##############################
##### AWS ALB CONTROLLER
##############################
resource "kubernetes_config_map_v1" "alb_controller" {
  immutable = true

  metadata {
    name      = "alb-controller-values-terraform"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "values.yaml" = yamlencode({
      clusterName = module.eks.cluster_name
      region      = var.aws_region
      vpcId       = module.vpc.vpc_id
    })
  }
}

module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "v2.6.0"

  name                            = "aws-load-balancer-controller"
  attach_aws_lb_controller_policy = true
  associations = {
    alb = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

##############################
##### KARPENTER
##############################
# Handles Resource Creation (SQS, EventBridge Rules, IAM Role, EKS Access Entry, Pod Identity Association)
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "v21.10.1"

  cluster_name         = module.eks.cluster_name
  create_node_iam_role = false
  node_iam_role_arn    = local.k8s_cluster_role_arn
  create_access_entry  = false
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  namespace = "karpenter"
}

resource "kubernetes_namespace_v1" "karpenter" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    name = "karpenter"
  }
}

resource "kubernetes_config_map_v1" "karpenter" {
  depends_on = [kubernetes_namespace_v1.karpenter]
  immutable  = true

  metadata {
    name      = "karpenter-values-terraform"
    namespace = "karpenter"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "values.yaml" = yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        interruptionQueue = module.karpenter.queue_name
      }
    })
  }
}

##############################
##### AUTHENTIK
##############################
resource "random_password" "authentik_secret" {
  length  = 64
  special = false
}

resource "random_password" "authentik_admin_password" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "authentik_secret" {
  name                    = "authentik/secret-key"
  recovery_window_in_days = var.secret_recovery_window
}

resource "aws_secretsmanager_secret_version" "authentik_secret_value" {
  secret_id = aws_secretsmanager_secret.authentik_secret.id
  secret_string = jsonencode({
    secretKey     = random_password.authentik_secret.result
    adminEmail    = "admin@admin.com"
    adminPassword = aws_secretsmanager_secret.authentik_admin_password.id
  })
}

resource "kubernetes_namespace_v1" "authentik" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    name = "authentik"
  }
}

resource "kubernetes_config_map_v1" "authentik" {
  depends_on = [kubernetes_namespace_v1.authentik]
  immutable  = true

  metadata {
    name      = "authentik-values-terraform"
    namespace = "authentik"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "values.yaml" = yamlencode({
      authentik = {
        postgresql = {
          host = module.db_authentik.db_instance_address
        }
      }
    })
  }
}

##############################
##### HEADLAMP
##############################
resource "random_password" "headlamp_client_id" {
  length  = 40
  special = false
}

resource "random_password" "headlamp_client_secret" {
  length  = 128
  special = false
}

resource "aws_secretsmanager_secret" "headlamp_secret" {
  name                    = "headlamp/oidc"
  description             = "Stores OIDC related settings"
  recovery_window_in_days = var.secret_recovery_window
}

resource "aws_secretsmanager_secret_version" "headlamp_secret" {
  secret_id = aws_secretsmanager_secret.headlamp_secret.id
  secret_string = jsonencode({
    clientID     = random_password.headlamp_client_id.result
    clientSecret = random_password.headlamp_client_secret.result
    issuerURL    = "https://authentik.${var.domain}/application/o/headlamp/"
    scopes       = "profile,email,groups"
  })
}
