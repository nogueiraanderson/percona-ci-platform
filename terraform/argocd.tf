# ArgoCD bootstrap (GitOps Bridge pattern):
# 1. helm_release for the argo-cd chart
# 2. kubernetes Secret with annotations carrying TF outputs (cluster name, OIDC, role ARNs, ACM ARN, etc.)
# 3. Root Application pointing at argocd-bootstrap/ in this repo

# resource "helm_release" "argocd" {
#   name             = "argocd"
#   namespace        = "argocd"
#   repository       = local.charts.argo_cd.repo
#   chart            = local.charts.argo_cd.name
#   version          = local.charts.argo_cd.ver
#   create_namespace = true
#
#   values = [yamlencode({
#     global = { domain = var.argocd_hostname }
#     controller     = { replicas = 2 }
#     redis-ha       = { enabled = true }
#     server         = { replicas = 2, ingress = { enabled = false } }
#     repoServer     = { replicas = 2 }
#     applicationSet = { replicas = 2 }
#   })]
#
#   depends_on = [module.eks]
# }

# resource "kubernetes_secret_v1" "argocd_cluster" {
#   metadata {
#     name      = "in-cluster"
#     namespace = "argocd"
#     labels = {
#       "argocd.argoproj.io/secret-type" = "cluster"
#       "enabled"                        = "true"
#     }
#     annotations = {
#       cluster_name             = module.eks.cluster_name
#       aws_account_id           = data.aws_caller_identity.current.account_id
#       aws_region               = var.aws_region
#       oidc_provider_arn        = module.eks.oidc_provider_arn
#       acm_wildcard_arn         = module.acm.acm_certificate_arn
#       karpenter_sqs_name       = module.karpenter.queue_name
#       alb_controller_role_arn  = module.pod_identity_alb.iam_role_arn
#       external_dns_role_arn    = module.pod_identity_external_dns.iam_role_arn
#       ebs_csi_role_arn         = module.pod_identity_ebs_csi.iam_role_arn
#       external_secrets_role_arn = module.pod_identity_external_secrets.iam_role_arn
#     }
#   }
#   data = {
#     name   = module.eks.cluster_name
#     server = "https://kubernetes.default.svc"
#     config = jsonencode({ tlsClientConfig = { insecure = false } })
#   }
#   depends_on = [helm_release.argocd]
# }

# resource "kubectl_manifest" "argocd_root_app" {
#   yaml_body  = file("${path.module}/../argocd-bootstrap/root-app.yaml")
#   depends_on = [kubernetes_secret_v1.argocd_cluster]
# }

# data "aws_caller_identity" "current" {}
