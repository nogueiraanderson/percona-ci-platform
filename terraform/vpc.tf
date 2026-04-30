# Cluster VPC. CIDR avoids the Jenkins-VPC ranges (var.vpc_cidr default 10.220.0.0/16).
# Subnets carry the EKS LB-controller tags (kubernetes.io/role/elb, internal-elb).
#
# TODO: implement on first apply pass. Skeleton below; uncomment and review before enabling.
#
# Hardening (see docs/eks-hardening.md):
#  11. enable_s3_endpoint = true (free gateway endpoint, drops NAT-GW egress for ECR-pull
#      object reads + Helm chart downloads). Interface endpoints (ECR / STS / Secrets
#      Manager) are paid; revisit when NAT-GW bill warrants.

# module "vpc" {
#   source  = local.modules.vpc.source
#   version = local.modules.vpc.version
#
#   name = "${local.cluster_name}-vpc"
#   cidr = var.vpc_cidr
#
#   azs              = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
#   private_subnets  = ["10.220.0.0/19", "10.220.32.0/19", "10.220.64.0/19"]
#   public_subnets   = ["10.220.96.0/24", "10.220.97.0/24", "10.220.98.0/24"]
#
#   enable_nat_gateway   = true
#   single_nat_gateway   = false # one NAT per AZ for HA; if cost-trimming, switch to single
#   enable_dns_hostnames = true
#
#   public_subnet_tags = {
#     "kubernetes.io/role/elb" = 1
#   }
#   private_subnet_tags = {
#     "kubernetes.io/role/internal-elb" = 1
#     "karpenter.sh/discovery"          = local.cluster_name
#   }
#
#   tags = local.tags
# }
