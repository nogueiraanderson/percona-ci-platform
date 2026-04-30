# Wildcard ACM cert for *.cd.percona.com, validated via DNS in the existing public hosted zone.

# data "aws_route53_zone" "main" {
#   name         = var.route53_zone_name
#   private_zone = false
# }

# module "acm" {
#   source  = local.modules.acm.source
#   version = local.modules.acm.version
#
#   domain_name = "*.${var.route53_zone_name}"
#   subject_alternative_names = [var.route53_zone_name]
#
#   zone_id           = data.aws_route53_zone.main.zone_id
#   validation_method = "DNS"
#   wait_for_validation = true
#
#   tags = local.tags
# }
