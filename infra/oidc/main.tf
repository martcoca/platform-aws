data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  oidc_host         = "token.actions.githubusercontent.com"
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_host}"
  state_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket_name}"
  state_object_arn  = "${local.state_bucket_arn}/${var.state_key}"
  lock_object_arn   = "${local.state_object_arn}.tflock"
  trusted_subject   = "repo:${var.github_repository}:ref:${var.github_ref}"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://${local.oidc_host}"

  client_id_list = [
    "sts.amazonaws.com",
  ]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid     = "GitHubActionsFromExactRef"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.trusted_subject]
    }
  }
}

resource "aws_iam_role" "github_actions_plan" {
  name                 = var.role_name
  description          = "Short-lived GitHub Actions role for platform-aws plans and state"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600

  depends_on = [
    aws_iam_openid_connect_provider.github_actions,
  ]
}

data "aws_iam_policy_document" "t03_plan_and_state" {
  statement {
    sid       = "ReadStateBucketLocation"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "ListOnlyStateAndLockObjects"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values = [
        var.state_key,
        "${var.state_key}.tflock",
      ]
    }
  }

  statement {
    sid    = "ReadAndWriteStateAndLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      local.state_object_arn,
      local.lock_object_arn,
    ]
  }

  statement {
    sid       = "DeleteOnlyStateLock"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = [local.lock_object_arn]
  }
}

resource "aws_iam_role_policy" "t03_plan_and_state" {
  name   = "t03-plan-and-state"
  role   = aws_iam_role.github_actions_plan.id
  policy = data.aws_iam_policy_document.t03_plan_and_state.json
}
