variable "cors_allowed_origins" {
  description = "Browser origins allowed to call the API"
  type        = list(string)
  default     = ["http://localhost:5173"]
}

variable "ses_sender_email" {
  description = "Verified SES sender address for share notification emails"
  type        = string
  default     = "abhinavrag777@gmail.com"
}
