output "github_actions_role_arn" {
  description = "Store this non-secret value as the AWS_OIDC_ROLE_ARN GitHub Actions repository variable."
  value       = aws_iam_role.github_actions_plan.arn
}

output "trusted_subject" {
  description = "Exact GitHub OIDC subject accepted by the role trust policy."
  value       = local.trusted_subject
}

