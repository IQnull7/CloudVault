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

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "jwt_issuer" {
  value = "https://${aws_cognito_user_pool.main.endpoint}"
}
output "api_endpoint" {
  value = aws_apigatewayv2_api.main.api_endpoint
}