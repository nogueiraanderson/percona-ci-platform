# Outputs are populated as resources land. Filling these out drives the
# argocd cluster-secret annotations contract (see argocd.tf when implemented).

# output "cluster_name" {
#   value = module.eks.cluster_name
# }
#
# output "cluster_endpoint" {
#   value = module.eks.cluster_endpoint
# }
#
# output "oidc_provider_arn" {
#   value = module.eks.oidc_provider_arn
# }
#
# output "vpc_id" {
#   value = module.vpc.vpc_id
# }
#
# output "acm_wildcard_arn" {
#   value = module.acm.acm_certificate_arn
# }
