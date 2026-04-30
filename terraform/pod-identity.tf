# Pod Identity associations (5 total). Each block uses the pod-identity module's
# built-in policy preset (`attach_<addon>_policy = true`) so we don't hand-write IAM.
# Karpenter's association is created inside the karpenter prereq module above.

# module "pod_identity_alb" {
#   source  = local.modules.pod_identity.source
#   version = local.modules.pod_identity.version
#
#   name                            = "${local.cluster_name}-aws-lb-controller"
#   attach_aws_lb_controller_policy = true
#
#   associations = {
#     main = {
#       cluster_name    = module.eks.cluster_name
#       namespace       = "kube-system"
#       service_account = "aws-load-balancer-controller"
#     }
#   }
#   tags = local.tags
# }

# module "pod_identity_external_dns" {
#   source  = local.modules.pod_identity.source
#   version = local.modules.pod_identity.version
#
#   name                  = "${local.cluster_name}-external-dns"
#   attach_external_dns_policy = true
#   external_dns_hosted_zone_arns = [data.aws_route53_zone.main.arn]
#
#   associations = {
#     main = {
#       cluster_name    = module.eks.cluster_name
#       namespace       = "external-dns"
#       service_account = "external-dns"
#     }
#   }
#   tags = local.tags
# }

# module "pod_identity_ebs_csi" {
#   source  = local.modules.pod_identity.source
#   version = local.modules.pod_identity.version
#
#   name                  = "${local.cluster_name}-ebs-csi"
#   attach_aws_ebs_csi_policy = true
#
#   associations = {
#     main = {
#       cluster_name    = module.eks.cluster_name
#       namespace       = "kube-system"
#       service_account = "ebs-csi-controller-sa"
#     }
#   }
#   tags = local.tags
# }

# module "pod_identity_external_secrets" {
#   source  = local.modules.pod_identity.source
#   version = local.modules.pod_identity.version
#
#   name = "${local.cluster_name}-external-secrets"
#   policy_statements = [
#     {
#       sid    = "SecretsManagerRead"
#       effect = "Allow"
#       actions = [
#         "secretsmanager:GetSecretValue",
#         "secretsmanager:DescribeSecret",
#         "secretsmanager:ListSecrets",
#       ]
#       resources = ["*"]
#     }
#   ]
#   associations = {
#     main = {
#       cluster_name    = module.eks.cluster_name
#       namespace       = "external-secrets"
#       service_account = "external-secrets"
#     }
#   }
#   tags = local.tags
# }
