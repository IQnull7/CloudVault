variable "cors_allowed_origins" {
  description = "Browser origins allowed to call the API"
  type        = list(string)
  default     = ["http://localhost:5173"]
}