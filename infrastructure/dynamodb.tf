resource "aws_dynamodb_table" "files" {
  name         = "CloudVault-Files"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fileId"

  attribute {
    name = "fileId"
    type = "S"
  }
  attribute {
    name = "ownerEmail"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "N"
  }

  global_secondary_index {
    name            = "owner-index"
    hash_key        = "ownerEmail"
    range_key       = "createdAt"
    projection_type = "ALL"
  }
}

resource "aws_dynamodb_table" "shares" {
  name         = "CloudVault-Shares"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fileId"
  range_key    = "recipientEmail"

  attribute {
    name = "fileId"
    type = "S"
  }
  attribute {
    name = "recipientEmail"
    type = "S"
  }

  global_secondary_index {
    name            = "recipient-index"
    hash_key        = "recipientEmail"
    range_key       = "fileId"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "audit_logs" {
  name         = "CloudVault-AuditLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fileId"
  range_key    = "sk"

  attribute {
    name = "fileId"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "actorEmail"
    type = "S"
  }
  attribute {
    name = "ts"
    type = "N"
  }

  global_secondary_index {
    name            = "actor-index"
    hash_key        = "actorEmail"
    range_key       = "ts"
    projection_type = "ALL"
  }
}