resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/lambda/CloudVault-access"
  retention_in_days = 7
}

resource "aws_iam_role" "access" {
  name               = "CloudVault-access-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "access" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.access.arn}:*"]
  }
  statement {
    sid       = "ReadFile"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
  statement {
    sid       = "ReadShare"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.shares.arn]
  }
  statement {
    sid       = "GetS3Object"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.cloudvault.arn}/uploads/*"]
  }
  statement {
    sid       = "AppendAudit"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit_logs.arn]
  }
}

resource "aws_iam_role_policy" "access" {
  name   = "access-least-privilege"
  role   = aws_iam_role.access.id
  policy = data.aws_iam_policy_document.access.json
}

resource "aws_lambda_function" "access" {
  function_name    = "CloudVault-access"
  role             = aws_iam_role.access.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/access.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      BUCKET_NAME  = aws_s3_bucket.cloudvault.bucket
      FILES_TABLE  = aws_dynamodb_table.files.name
      SHARES_TABLE = aws_dynamodb_table.shares.name
      AUDIT_TABLE  = aws_dynamodb_table.audit_logs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.access]
}

resource "aws_apigatewayv2_integration" "access" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.access.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "access" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /files/{id}/access"
  target             = "integrations/${aws_apigatewayv2_integration.access.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "access" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.access.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/GET/files/*/access"
}

