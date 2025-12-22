##############################
##### BOOTSTRAP FLUX
##############################
resource "flux_bootstrap_git" "this" {
  depends_on = [
    kubernetes_config_map_v1.cluster_vars,
    kubernetes_namespace.external_dns,
    kubernetes_namespace.karpenter
  ]

  path    = local.flux_bootstrap_path
  version = var.flux_version
}

resource "github_repository_file" "flux_bootstrap_crds" {
  repository          = var.repository_name
  branch              = "main"
  file                = "${local.flux_bootstrap_path}/flux-system/crds.yaml"
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
  commit_message      = "bootstrap Flux"
  overwrite_on_create = true
}

resource "github_repository_file" "flux_bootstrap_addons" {
  repository          = var.repository_name
  branch              = "main"
  file                = "${local.flux_bootstrap_path}/flux-system/addons.yaml"
  content             = <<-YAML
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system-crds
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./k8s/addons/${var.environment}
  prune: true
  dependsOn:
    - name: crds
  sourceRef:
    kind: GitRepository
    name: flux-system
  postBuild:
    value:
      substituteFrom:
        - kind: ConfigMap
          name: cluster-vars-terraform
YAML
  commit_message      = "bootstrap Flux"
  overwrite_on_create = true
}

resource "kubernetes_config_map_v1" "cluster_vars" {
  immutable = true

  metadata {
    name      = "cluster-vars-terraform"
    namespace = "flux-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "TF_AWS_REGION"         = var.aws_region
    "TF_ACM_CERT_ARN"       = local.acm_certificate_arn
    "TF_HEADLAMP_HOSTNAME"  = "headlamp.${var.domain}"
    "TF_CLUSTER_NAME"       = local.k8s_cluster_name
    "TF_K8S_NODE_ROLE_NAME" = module.eks.eks_managed_node_groups["general-purpose"].iam_role_name
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
  version = "v2.2.0"

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

resource "kubernetes_namespace" "external_dns" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    name = "external-dns"
  }
}

resource "kubernetes_config_map_v1" "external_dns" {
  depends_on = [flux_bootstrap_git.this, kubernetes_namespace.external_dns]
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
  version = "v2.2.0"

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
  depends_on = [flux_bootstrap_git.this]
  immutable  = true

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
  version = "v2.5.0"

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
  source     = "terraform-aws-modules/eks/aws//modules/karpenter"
  version    = "v21.10.1"
  depends_on = [flux_bootstrap_git.this]

  cluster_name = module.eks.cluster_name
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  namespace = "karpenter"
}

resource "kubernetes_namespace" "karpenter" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    name = "karpenter"
  }
}

resource "kubernetes_config_map_v1" "karpenter" {
  depends_on = [kubernetes_namespace.external_dns]
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
# resource "random_password" "authentik_secret" {
#   length  = 64
#   special = false
# }

# resource "aws_secretsmanager_secret" "authentik_secret" {
#   name = "authentik/secret-key"
# }

# resource "aws_secretsmanager_secret_version" "authentik_secret_value" {
#   secret_id     = aws_secretsmanager_secret.authentik_secret.id
#   secret_string = random_password.authentik_secret.result
# }
