# ---------- Package the backend (shared by all Lambdas) ----------
data "archive_file" "backend" {
  type        = "zip"
  source_dir  = "${path.module}/../backend"
  output_path = "${path.module}/build/backend.zip"
}

# ---------- upload-url Lambda ----------
resource "aws_cloudwatch_log_group" "upload_url" {
  name              = "/aws/lambda/CloudVault-upload-url"
  retention_in_days = 7
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "upload_url" {
  name               = "CloudVault-upload-url-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "upload_url" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.upload_url.arn}:*"]
  }
  statement {
    sid       = "PutUploads"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudvault.arn}/uploads/*"]
  }
  statement {
    sid       = "WritePendingRecord"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
}

resource "aws_iam_role_policy" "upload_url" {
  name   = "upload-url-least-privilege"
  role   = aws_iam_role.upload_url.id
  policy = data.aws_iam_policy_document.upload_url.json
}

resource "aws_lambda_function" "upload_url" {
  function_name    = "CloudVault-upload-url"
  role             = aws_iam_role.upload_url.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "src/uploadUrl.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cloudvault.bucket
      FILES_TABLE = aws_dynamodb_table.files.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.upload_url]
}

# ---------- Route: POST /files/upload-url ----------
resource "aws_apigatewayv2_integration" "upload_url" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload_url.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload_url" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /files/upload-url"
  target             = "integrations/${aws_apigatewayv2_integration.upload_url.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "upload_url" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/POST/files/upload-url"
}