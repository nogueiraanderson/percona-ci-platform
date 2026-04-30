# origin-<host>.cd.percona.com records — pointers to the existing Jenkins
# masters' public IPs so the friendly *.cd.percona.com can flip to the ALB
# without losing reachability to the underlying VM during cutover.
# Per-master public IP comes from the Jenkins-pipelines IaC (CFN/Terraform)
# in each of the 5 regions; we replicate just the DNS pointer here.
#
# TODO: source IPs from a tfvars file or data sources once the values are confirmed.

# locals {
#   origin_ips = {
#     pmm   = "REDACTED"
#     ps80  = "REDACTED"
#     # ...
#   }
# }

# resource "aws_route53_record" "origin" {
#   for_each = local.origin_ips
#   zone_id  = data.aws_route53_zone.main.zone_id
#   name     = "origin-${each.key}.${var.route53_zone_name}"
#   type     = "A"
#   ttl      = 300
#   records  = [each.value]
# }
