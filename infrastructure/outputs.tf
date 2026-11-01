output "bucket_name" {
  value = aws_s3_bucket.cloudvault.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.cloudvault.arn
}

output "files_table_name" {
  value = aws_dynamodb_table.files.name
}

output "shares_table_name" {
  value = aws_dynamodb_table.shares.name
}

output "audit_logs_table_name" {
  value = aws_dynamodb_table.audit_logs.name
}