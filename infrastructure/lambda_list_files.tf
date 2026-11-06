resource "aws_cloudwatch_log_group" "list_files" {
  name              = "/aws/lambda/CloudVault-list-files"
  retention_in_days = 7
}

resource "aws_iam_role" "list_files" {
  name               = "CloudVault-list-files-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "list_files" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.list_files.arn}:*"]
  }
  statement {
    sid     = "QueryOwnerIndex"
    actions = ["dynamodb:Query"]
    resources = [
      aws_dynamodb_table.files.arn,
      "${aws_dynamodb_table.files.arn}/index/owner-index",
    ]
  }
}

resource "aws_iam_role_policy" "list_files" {
  name   = "list-files-least-privilege"
  role   = aws_iam_role.list_files.id
  policy = data.aws_iam_policy_document.list_files.json
}

resource "aws_lambda_function" "list_files" {
  function_name    = "CloudVault-list-files"
  role             = aws_iam_role.list_files.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/listFiles.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      FILES_TABLE = aws_dynamodb_table.files.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.list_files]
}

resource "aws_apigatewayv2_integration" "list_files" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.list_files.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list_files" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /files"
  target             = "integrations/${aws_apigatewayv2_integration.list_files.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "list_files" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_files.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/GET/files"
}