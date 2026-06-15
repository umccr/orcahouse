# KMS key to encrypt pulumi state

resource "aws_kms_key" "pulumi_state_key" {
  description             = "Pulumi State Encryption Key for OrcaHouse Infrastructure"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Purpose = "Pulumi-State-Encryption"
  }
}

resource "aws_kms_alias" "pulumi_state_key_alias" {
  name          = "alias/pulumi-state-key"
  target_key_id = aws_kms_key.pulumi_state_key.key_id
}

resource "aws_kms_key_policy" "pulumi_state_key_policy" {
  key_id = aws_kms_key.pulumi_state_key.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Statement 1: Default IAM Policy (Enables root account delegation)
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # Statement 2: Limit Key Administration to the Break-Glass Admin Role Only
      {
        Sid    = "Allow Key Administration"
        Effect = "Allow"
        # 1. Broad principal allows evaluation to proceed to the condition block
        Principal = {
          AWS = "*"
        }
        # 2. Strict condition blocks anyone who doesn't match your SSO Role pattern
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/${data.aws_region.current.region}/AWSReservedSSO_AWSAdministratorAccess_*",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/${data.aws_region.current.region}/AWSReservedSSO_PlatformOwnerAccess_*"
            ]
          }
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },

      # Statement 3: Grant Encryption/Decryption Access ONLY to authorized Developers and CI/CD
      {
        Sid    = "Allow Pulumi Usage for Authorized Roles"
        Effect = "Allow"
        # 1. Broad principal allows evaluation to proceed to the condition block
        Principal = {
          AWS = "*"
        }
        # 2. Strict condition blocks anyone who doesn't match your SSO Role pattern
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/${data.aws_region.current.region}/AWSReservedSSO_AWSAdministratorAccess_*",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/${data.aws_region.current.region}/AWSReservedSSO_AWSPowerUserAccess_*"
            ]
          }
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}
