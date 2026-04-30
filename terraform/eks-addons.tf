# Managed EKS addons. eks-pod-identity-agent is mandatory for any Pod Identity
# association to function (without it every association silently no-ops).
#
# Hardening (must land before merging modules — see docs/eks-hardening.md):
#   4. vpc-cni: configuration_values = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true" } })
#      — 4× pod density on m6a.xlarge (58 → 234), fewer Karpenter scale-ups.
#   5. Pin every addon_version explicitly. No "latest". Look up via:
#      aws eks describe-addon-versions --kubernetes-version 1.35 --addon-name <name>
#  16. vpc-cni: enableNetworkPolicy=true so the native NP engine is available
#      before any default-deny baseline ships.

# resource "aws_eks_addon" "vpc_cni" {
#   cluster_name  = module.eks.cluster_name
#   addon_name    = "vpc-cni"
#   addon_version = "v1.x.x-eksbuild.x" # docs/eks-hardening.md #5 — pin
#   resolve_conflicts_on_create = "OVERWRITE"
#   # configuration_values = jsonencode({
#   #   env = { ENABLE_PREFIX_DELEGATION = "true" }   # docs/eks-hardening.md #4
#   #   enableNetworkPolicy = "true"                  # docs/eks-hardening.md #16
#   # })
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
