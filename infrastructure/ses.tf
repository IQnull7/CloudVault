# SES: verify the sender email identity (sandbox mode).
# A human must click the verification link that arrives in this inbox.
# See docs/HUMAN-TODO.md item 1.

resource "aws_ses_email_identity" "sender" {
  email = var.ses_sender_email
}

