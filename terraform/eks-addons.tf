# Managed EKS addons. eks-pod-identity-agent is mandatory for any Pod Identity
# association to function (without it every association silently no-ops).

# resource "aws_eks_addon" "vpc_cni" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "vpc-cni"
#   resolve_conflicts_on_create = "OVERWRITE"
# }

# resource "aws_eks_addon" "kube_proxy" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "kube-proxy"
#   resolve_conflicts_on_create = "OVERWRITE"
# }

# resource "aws_eks_addon" "coredns" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "coredns"
#   resolve_conflicts_on_create = "OVERWRITE"
# }

# resource "aws_eks_addon" "pod_identity_agent" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "eks-pod-identity-agent"
#   resolve_conflicts_on_create = "OVERWRITE"
# }

# resource "aws_eks_addon" "ebs_csi_driver" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "aws-ebs-csi-driver"
#   service_account_role_arn = module.pod_identity_ebs_csi.iam_role_arn
#   resolve_conflicts_on_create = "OVERWRITE"
# }
