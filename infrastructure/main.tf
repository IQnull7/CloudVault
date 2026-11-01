data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "cloudvault" {
  bucket = "cloudvault-files-${data.aws_caller_identity.current.account_id}-ap-southeast-2"
}

resource "aws_s3_bucket_public_access_block" "cloudvault" {
  bucket = aws_s3_bucket.cloudvault.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudvault" {
  bucket = aws_s3_bucket.cloudvault.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudvault" {
  bucket = aws_s3_bucket.cloudvault.id

  versioning_configuration {
    status = "Enabled"
  }
}