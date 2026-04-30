# AWS Backup plan for monitoring + Jenkins master PVCs (gp3 EBS volumes).
# Retain policy on the StorageClass only stops Kubernetes from deleting the
# volume; it doesn't protect against AZ outage, EBS corruption, or accidental
# snapshot deletion.

# resource "aws_backup_vault" "main" {
#   name        = "${local.cluster_name}-backups"
#   kms_key_arn = aws_kms_key.backup.arn
# }

# resource "aws_kms_key" "backup" {
#   description             = "AWS Backup vault encryption for ${local.cluster_name}"
#   deletion_window_in_days = 7
#   enable_key_rotation     = true
# }

# resource "aws_backup_plan" "daily" {
#   name = "${local.cluster_name}-daily"
#   rule {
#     rule_name         = "daily-3am"
#     target_vault_name = aws_backup_vault.main.name
#     schedule          = "cron(0 3 * * ? *)"
#     lifecycle { delete_after = 14 }
#   }
# }

# resource "aws_iam_role" "backup" {
#   name = "${local.cluster_name}-backup"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "backup.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "backup" {
#   role       = aws_iam_role.backup.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
# }

# resource "aws_backup_selection" "monitoring" {
#   name         = "monitoring-pvcs"
#   iam_role_arn = aws_iam_role.backup.arn
#   plan_id      = aws_backup_plan.daily.id
#   selection_tag {
#     type  = "STRINGEQUALS"
#     key   = "kubernetes.io/created-for/pvc/namespace"
#     value = "monitoring"
#   }
# }
#
# resource "aws_backup_selection" "jenkins" {
#   name         = "jenkins-pvcs"
#   iam_role_arn = aws_iam_role.backup.arn
#   plan_id      = aws_backup_plan.daily.id
#   selection_tag {
#     type  = "STRINGEQUALS"
#     key   = "app.kubernetes.io/component"
#     value = "jenkins-master"
#   }
# }
