# The two roles a stage needs: what its executions run as, and what starts them. Both are
# assumed by one AWS service in this account, so only that service differs.

locals {
  roles = {
    states = { service = "states.amazonaws.com" }
    start  = { service = var.starter_service }
  }
}

data "aws_iam_policy_document" "assume" {
  for_each = local.roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [each.value.service]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name               = "${local.name_prefix}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json
}

data "aws_iam_policy_document" "states" {
  # Anything the stage's states bring, such as sfn-crawl's crawlers.
  source_policy_documents = var.source_policy_documents

  dynamic "statement" {
    for_each = local.states_statements

    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "states" {
  name   = "${local.name_prefix}-states-policy"
  role   = aws_iam_role.this["states"].id
  policy = data.aws_iam_policy_document.states.json
}

data "aws_iam_policy_document" "start" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.this.arn]
  }
}

resource "aws_iam_role_policy" "start" {
  name   = "${local.name_prefix}-start-policy"
  role   = aws_iam_role.this["start"].id
  policy = data.aws_iam_policy_document.start.json
}
