variable "aws_region" {
  description = "AWS region used for provider operations."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "This platform-aws stack is fixed to us-east-1."
  }
}

variable "github_repository" {
  description = <<-EOT
    GitHub repository allowed to federate, exactly as it appears in the OIDC `sub` claim.

    GitHub may issue *immutable* subject claims that append numeric ids to both the owner
    and the repository — `owner@1234/name@5678` rather than `owner/name`. That form is
    resistant to name-reuse attacks: deleting a repository and recreating it under the
    same name yields a new id and no longer matches. Prefer it where it is issued.

    Confirm the value a run actually presents before trusting a guess; a mismatch fails
    closed with "Not authorized to perform sts:AssumeRoleWithWebIdentity".
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^/[:space:]]+/[^/[:space:]]+$", var.github_repository))
    error_message = "github_repository must be one owner/name pair, with no slash or whitespace inside either part."
  }
}

variable "github_ref" {
  description = "One exact Git ref allowed to federate, such as refs/heads/oidc-check."
  type        = string

  validation {
    condition     = can(regex("^refs/(heads|tags)/[^[:space:]*?]+$", var.github_ref))
    error_message = "github_ref must be one exact branch or tag ref without wildcards."
  }
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket that T03 uses for OpenTofu state."
  type        = string

  validation {
    condition = (
      length(var.state_bucket_name) >= 3 &&
      length(var.state_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.state_bucket_name))
    )
    error_message = "state_bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "role_name" {
  description = "Name of the GitHub Actions planning role."
  type        = string
  default     = "github-actions-platform-aws-plan"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must satisfy the IAM role-name character and length limits."
  }
}
