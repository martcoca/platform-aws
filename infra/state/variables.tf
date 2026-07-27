variable "aws_region" {
  description = "AWS region used for the state bucket."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "This platform-aws stack is fixed to us-east-1."
  }
}

variable "state_bucket_name" {
  description = "Globally unique name of the S3 bucket that holds OpenTofu state."
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
