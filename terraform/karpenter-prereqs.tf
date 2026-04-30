# Karpenter IAM + SQS prerequisites (the controller, NodePool, and EC2NodeClass
# manifests live in resources/addons/karpenter/, applied by ArgoCD).

# module "karpenter" {
#   source  = local.modules.karpenter.source
#   version = local.modules.karpenter.version
#
#   cluster_name = module.eks.cluster_name
#
#   enable_v1_permissions = true
#   enable_pod_identity   = true                  # Pod Identity, not IRSA
#   create_pod_identity_association = true
#
#   node_iam_role_use_name_prefix = false
#   node_iam_role_name            = "${local.cluster_name}-karpenter-node"
#
#   tags = local.tags
# }
