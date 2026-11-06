resource "aws_cloudwatch_log_group" "revoke_share" {
  name              = "/aws/lambda/CloudVault-revoke-share"
  retention_in_days = 7
}

resource "aws_iam_role" "revoke_share" {
  name               = "CloudVault-revoke-share-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "revoke_share" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.revoke_share.arn}:*"]
  }
  statement {
    sid       = "ReadFile"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
  statement {
    sid       = "DeleteShare"
    actions   = ["dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.shares.arn]
  }
  statement {
    sid       = "AppendAudit"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit_logs.arn]
  }
}

resource "aws_iam_role_policy" "revoke_share" {
  name   = "revoke-share-least-privilege"
  role   = aws_iam_role.revoke_share.id
  policy = data.aws_iam_policy_document.revoke_share.json
}

resource "aws_lambda_function" "revoke_share" {
  function_name    = "CloudVault-revoke-share"
  role             = aws_iam_role.revoke_share.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/revokeShare.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      FILES_TABLE  = aws_dynamodb_table.files.name
      SHARES_TABLE = aws_dynamodb_table.shares.name
      AUDIT_TABLE  = aws_dynamodb_table.audit_logs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.revoke_share]
}

resource "aws_apigatewayv2_integration" "revoke_share" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.revoke_share.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "revoke_share" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "DELETE /files/{id}/share"
  target             = "integrations/${aws_apigatewayv2_integration.revoke_share.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "revoke_share" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.revoke_share.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/DELETE/files/*/share"
}

