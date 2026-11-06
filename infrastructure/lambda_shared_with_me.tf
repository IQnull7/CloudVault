resource "aws_cloudwatch_log_group" "shared_with_me" {
  name              = "/aws/lambda/CloudVault-shared-with-me"
  retention_in_days = 7
}

resource "aws_iam_role" "shared_with_me" {
  name               = "CloudVault-shared-with-me-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "shared_with_me" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.shared_with_me.arn}:*"]
  }
  statement {
    sid     = "QueryRecipientIndex"
    actions = ["dynamodb:Query"]
    resources = [
      aws_dynamodb_table.shares.arn,
      "${aws_dynamodb_table.shares.arn}/index/recipient-index",
    ]
  }
  statement {
    sid       = "BatchGetFiles"
    actions   = ["dynamodb:BatchGetItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
}

resource "aws_iam_role_policy" "shared_with_me" {
  name   = "shared-with-me-least-privilege"
  role   = aws_iam_role.shared_with_me.id
  policy = data.aws_iam_policy_document.shared_with_me.json
}

resource "aws_lambda_function" "shared_with_me" {
  function_name    = "CloudVault-shared-with-me"
  role             = aws_iam_role.shared_with_me.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/sharedWithMe.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      FILES_TABLE  = aws_dynamodb_table.files.name
      SHARES_TABLE = aws_dynamodb_table.shares.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.shared_with_me]
}

resource "aws_apigatewayv2_integration" "shared_with_me" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.shared_with_me.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "shared_with_me" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /files/shared"
  target             = "integrations/${aws_apigatewayv2_integration.shared_with_me.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "shared_with_me" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shared_with_me.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/GET/files/shared"
}

