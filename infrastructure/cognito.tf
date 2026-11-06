resource "aws_cognito_user_pool" "main" {
  name = "CloudVault-Users"

  # Users sign in with their email address instead of a separate username
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Authenticator-app MFA is available but optional
  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email is required and cannot be changed after sign-up
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "CloudVault-Web"
  user_pool_id = aws_cognito_user_pool.main.id

  # A browser app cannot keep a secret, so no client secret
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 7

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}