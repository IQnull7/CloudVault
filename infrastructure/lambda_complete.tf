resource "aws_cloudwatch_log_group" "complete" {
  name              = "/aws/lambda/CloudVault-complete"
  retention_in_days = 7
}

resource "aws_iam_role" "complete" {
  name               = "CloudVault-complete-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "complete" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.complete.arn}:*"]
  }
  statement {
    sid       = "HeadUploadedObject"
    actions   = ["s3:GetObject"] # HeadObject is authorized by s3:GetObject
    resources = ["${aws_s3_bucket.cloudvault.arn}/uploads/*"]
  }
  statement {
    sid       = "ReadAndFinalizeFileRecord"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
  statement {
    sid       = "AppendAudit"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit_logs.arn]
  }
}

resource "aws_iam_role_policy" "complete" {
  name   = "complete-least-privilege"
  role   = aws_iam_role.complete.id
  policy = data.aws_iam_policy_document.complete.json
}

resource "aws_lambda_function" "complete" {
  function_name    = "CloudVault-complete"
  role             = aws_iam_role.complete.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/complete.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cloudvault.bucket
      FILES_TABLE = aws_dynamodb_table.files.name
      AUDIT_TABLE = aws_dynamodb_table.audit_logs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.complete]
}

resource "aws_apigatewayv2_integration" "complete" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.complete.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "complete" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /files/{id}/complete"
  target             = "integrations/${aws_apigatewayv2_integration.complete.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "complete" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.complete.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/POST/files/*/complete"
}