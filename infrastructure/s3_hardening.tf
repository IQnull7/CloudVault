# S3 hardening: CORS for browser uploads + deny non-TLS bucket policy.
# These are NEW sibling resources; they do NOT touch aws_s3_bucket.cloudvault.

resource "aws_s3_bucket_cors_configuration" "cloudvault" {
  bucket = aws_s3_bucket.cloudvault.id

  cors_rule {
    allowed_origins = local.all_allowed_origins
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }

  depends_on = [aws_s3_bucket_public_access_block.cloudvault]
}

data "aws_iam_policy_document" "cloudvault_bucket_policy" {
  statement {
    sid     = "DenyNonTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.cloudvault.arn,
      "${aws_s3_bucket.cloudvault.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudvault" {
  bucket = aws_s3_bucket.cloudvault.id
  policy = data.aws_iam_policy_document.cloudvault_bucket_policy.json

  # Must apply after public-access block is in place, otherwise policy attachment
  # can race with the block_public_policy setting.
  depends_on = [aws_s3_bucket_public_access_block.cloudvault]
}

