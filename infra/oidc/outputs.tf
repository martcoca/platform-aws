output "github_actions_role_arn" {
  description = "Store this value as the AWS_OIDC_ROLE_ARN GitHub Actions repository secret."
  value       = aws_iam_role.github_actions_plan.arn
}

output "trusted_subjects" {
  description = "Exact GitHub OIDC subjects accepted by the role trust policy."
  value = [
    local.trusted_ref_subject,
    local.trusted_pull_request_subject,
  ]
}
