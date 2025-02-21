################################################################################
# AWS Backup configuration for Aurora DB

data "aws_kms_key" "backup" {
  key_id = "alias/aws/backup"
}

resource "aws_iam_role" "db_backup_role" {
  name               = "${local.stack_name}-backup-role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Effect": "allow",
      "Principal": {
        "Service": ["backup.amazonaws.com"]
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "db_backup_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.db_backup_role.name
}

resource "aws_iam_role_policy_attachment" "db_backup_role_restore_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.db_backup_role.name
}

resource "aws_backup_vault" "db_backup_vault" {
  name  = "${local.stack_name}-backup-vault"
  kms_key_arn = data.aws_kms_key.backup.arn
}

resource "aws_backup_plan" "db_backup_plan" {
  name  = "${local.stack_name}-backup-plan"

  // Backup weekly and keep it for 6 weeks
  // Cron At 17:00 on every Sunday UTC = AEST/AEDT 3AM/4AM on every Monday
  rule {
    rule_name         = "Weekly"
    target_vault_name = aws_backup_vault.db_backup_vault.name
    schedule          = "cron(0 17 ? * SUN *)"

    lifecycle {
      delete_after = 42
    }
  }
}

resource "aws_backup_selection" "db_backup" {
  name         = "${local.stack_name}-backup"
  plan_id      = aws_backup_plan.db_backup_plan.id
  iam_role_arn = aws_iam_role.db_backup_role.arn

  resources = [
    aws_rds_cluster.this.arn,
  ]
}
