terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "student_name" {
  type    = string
  default = "peserta"
}

# S3 bucket names must be globally unique across ALL AWS accounts, not just
# within this account. Using only resource_prefix + student_name is not
# enough (collides with leftover buckets from previous deploys or other
# students using the same default name) — append the account ID as well.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "assets" {
  bucket        = "${var.resource_prefix}-assets-${var.student_name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "${var.resource_prefix}-assets-${var.student_name}" }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" { value = aws_s3_bucket.assets.bucket }
output "bucket_arn" { value = aws_s3_bucket.assets.arn }
