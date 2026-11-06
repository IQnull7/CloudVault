resource "aws_cloudwatch_log_group" "audit_log" {
  name              = "/aws/lambda/CloudVault-audit-log"
  retention_in_days = 7
}

resource "aws_iam_role" "audit_log" {
  name               = "CloudVault-audit-log-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "audit_log" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.audit_log.arn}:*"]
  }
  statement {
    sid       = "ReadFile"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
  statement {
    sid       = "QueryAuditLogs"
    actions   = ["dynamodb:Query"]
    resources = [aws_dynamodb_table.audit_logs.arn]
  }
}

resource "aws_iam_role_policy" "audit_log" {
  name   = "audit-log-least-privilege"
  role   = aws_iam_role.audit_log.id
  policy = data.aws_iam_policy_document.audit_log.json
}

resource "aws_lambda_function" "audit_log" {
  function_name    = "CloudVault-audit-log"
  role             = aws_iam_role.audit_log.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/auditLog.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      FILES_TABLE = aws_dynamodb_table.files.name
      AUDIT_TABLE = aws_dynamodb_table.audit_logs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.audit_log]
}

resource "aws_apigatewayv2_integration" "audit_log" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.audit_log.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "audit_log" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /files/{id}/audit"
  target             = "integrations/${aws_apigatewayv2_integration.audit_log.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "audit_log" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.audit_log.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/GET/files/*/audit"
}

