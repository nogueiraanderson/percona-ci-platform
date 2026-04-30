# EKS control plane + three managed node groups (system, prometheus_system, jenkins_system).
# Karpenter handles workload nodes; managed NGs host stateful + bootstrap pods only.
#
# TODO: enable after vpc.tf. Skeleton below.
#
# Hardening (must land before merging modules — see docs/eks-hardening.md):
#   1. authentication_mode = "API"; bootstrap_cluster_creator_admin_permissions = false
#   2. cluster_endpoint_public_access_cidrs = [<allowlist>] — no public-unrestricted
#   3. cluster_enabled_log_types = ["audit", "authenticator", "api"]
#   9. encryption_config (customer-managed KMS CMK) for cluster secrets
#  10. metadata_options { http_tokens = "required", http_put_response_hop_limit = 1 }

# module "eks" {
#   source  = local.modules.eks.source
#   version = local.modules.eks.version
#
#   name               = local.cluster_name
#   kubernetes_version = var.cluster_version
#
#   endpoint_public_access = true
#   enable_irsa            = true
#
#   vpc_id     = module.vpc.vpc_id
#   subnet_ids = module.vpc.private_subnets
#
#   # docs/eks-hardening.md #1 — flip both to API + false before any human gets a kubeconfig.
#   authentication_mode                      = "API_AND_CONFIG_MAP" # → "API" once access entries are written
#   enable_cluster_creator_admin_permissions = true                 # → false
#
#   eks_managed_node_groups = {
#     system = {
#       instance_types = local.ng.system.instance_types
#       capacity_type  = "ON_DEMAND"
#       min_size       = local.ng.system.min_size
#       desired_size   = local.ng.system.desired_size
#       max_size       = local.ng.system.max_size
#       labels         = { "node-role" = "system" }
#     }
#
#     prometheus_system = {
#       instance_types = local.ng.prometheus_system.instance_types
#       capacity_type  = "ON_DEMAND"
#       min_size       = local.ng.prometheus_system.min_size
#       desired_size   = local.ng.prometheus_system.desired_size
#       max_size       = local.ng.prometheus_system.max_size
#       subnet_ids     = [module.vpc.private_subnets[0]] # var.monitoring_az pinned
#       labels         = { "workload" = "prometheus", "node-role" = "stateful" }
#       taints = [{
#         key    = "workload"
#         value  = "prometheus"
#         effect = "NO_SCHEDULE"
#       }]
#     }
#
#     jenkins_system = {
#       instance_types = local.ng.jenkins_system.instance_types
#       capacity_type  = "ON_DEMAND"
#       min_size       = local.ng.jenkins_system.min_size
#       desired_size   = local.ng.jenkins_system.desired_size
#       max_size       = local.ng.jenkins_system.max_size
#       subnet_ids     = [module.vpc.private_subnets[0]] # us-east-1a, EBS zonality
#       labels         = { "workload" = "jenkins", "node-role" = "stateful" }
#       taints = [{
#         key    = "workload"
#         value  = "jenkins"
#         effect = "NO_SCHEDULE"
#       }]
#     }
#   }
#
#   tags = local.tags
# }
