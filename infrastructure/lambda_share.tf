resource "aws_cloudwatch_log_group" "share" {
  name              = "/aws/lambda/CloudVault-share"
  retention_in_days = 7
}

resource "aws_iam_role" "share" {
  name               = "CloudVault-share-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "share" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.share.arn}:*"]
  }
  statement {
    sid       = "ReadFile"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
  statement {
    sid       = "WriteShare"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.shares.arn]
  }
  statement {
    sid       = "AppendAudit"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit_logs.arn]
  }
  statement {
    sid       = "SendEmail"
    actions   = ["ses:SendEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "share" {
  name   = "share-least-privilege"
  role   = aws_iam_role.share.id
  policy = data.aws_iam_policy_document.share.json
}

resource "aws_lambda_function" "share" {
  function_name    = "CloudVault-share"
  role             = aws_iam_role.share.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/share.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      FILES_TABLE      = aws_dynamodb_table.files.name
      SHARES_TABLE     = aws_dynamodb_table.shares.name
      AUDIT_TABLE      = aws_dynamodb_table.audit_logs.name
      SES_SENDER_EMAIL = var.ses_sender_email
      AWS_SES_REGION   = "ap-southeast-2"
    }
  }

  depends_on = [aws_cloudwatch_log_group.share]
}

resource "aws_apigatewayv2_integration" "share" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.share.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "share" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /files/{id}/share"
  target             = "integrations/${aws_apigatewayv2_integration.share.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "share" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.share.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/POST/files/*/share"
}

