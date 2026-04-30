# EKS control plane + three managed node groups (system, prometheus_system, jenkins_system).
# Karpenter handles workload nodes; managed NGs host stateful + bootstrap pods only.
#
# TODO: enable after vpc.tf. Skeleton below.

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
#   # Cluster admin via current AWS principal — keep the bootstrap convenient.
#   enable_cluster_creator_admin_permissions = true
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
