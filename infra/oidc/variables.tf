variable "aws_region" {
  description = "AWS region used for provider operations."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "This foundation stack is fixed to us-east-1."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to federate, in owner/name form."
  type        = string

  validation {
    condition     = can(regex("^[^/[:space:]]+/[^/[:space:]]+$", var.github_repository))
    error_message = "github_repository must use the exact owner/name form."
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

variable "state_key" {
  description = "Exact S3 object key used for the T03 OpenTofu state."
  type        = string
  default     = "foundation/tofu.tfstate"

  validation {
    condition = (
      length(var.state_key) > 0 &&
      !startswith(var.state_key, "/") &&
      !endswith(var.state_key, ".tflock") &&
      !strcontains(var.state_key, "*") &&
      !strcontains(var.state_key, "?")
    )
    error_message = "state_key must be one exact state object key without a leading slash, lock suffix, or wildcards."
  }
}

variable "role_name" {
  description = "Name of the GitHub Actions planning role."
  type        = string
  default     = "github-actions-foundation-plan"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must satisfy the IAM role-name character and length limits."
  }
}

