# CloudVault – Human Action Required

These items need a human because they require browser clicks, real email verification, or a final manual review. They are listed in priority order.

---

## 1. SES Sender Verification (Required for share email notifications)

**Status:** Infrastructure created but emails not verified in SES sandbox.

The share Lambda is wired to send notification emails. SES in Sydney (`ap-southeast-2`) starts in sandbox mode, which means **both the sender and all recipients must have their email addresses verified** before any email can be sent.

**Steps:**
1. Open the AWS Console → **Simple Email Service** → **Verified identities** (Sydney region).
2. Click **Create identity** → choose **Email address**.
3. Enter: `abhinavrag777@gmail.com` (or whatever sender email you configure in `variables.tf` → `ses_sender_email`).
4. Click the verification link that arrives in that inbox.
5. Repeat for any recipient email addresses you want to test with (e.g., `abhinavrag777+agent-recipient@gmail.com`).
6. Once verified, re-run `scripts/e2e-test.ps1` to confirm the share flow sends an email.

> [!NOTE]
> The share Lambda is coded to **not fail** if SES sending fails — it logs to CloudWatch and returns 200 anyway. So shares work even without this step; you just won't receive notification emails.

---

## 2. Final browser login check (Phase 4 – Frontend)

Once the React frontend is deployed via CloudFront:
- Log in as both the owner and recipient in a real browser.
- Confirm the upload → share → access → revoke flow works end-to-end in the UI.
- Confirm the audit log view shows all events.

---

## 3. Remove ALLOW_USER_PASSWORD_AUTH before final submission (Phase 7)

The Cognito app client currently has `ALLOW_USER_PASSWORD_AUTH` enabled for dev/test convenience. **This must be removed before the final project submission.**

This is a gate-sanctioned change: the plan gate will allow it as the one sanctioned Cognito client update.

Steps (when ready):
```powershell
cd infrastructure
terraform plan -out=tfplan   # review: only aws_cognito_user_pool_client.web changes
powershell -ExecutionPolicy Bypass -File ..\scripts\plan-gate.ps1
terraform apply tfplan
```

---

## 4. Delete agent test users (Phase 7)

At the end of the project, delete the two agent-created Cognito users:
- `abhinavrag777+agent-owner@gmail.com`
- `abhinavrag777+agent-recipient@gmail.com`

```powershell
$env:AWS_PROFILE="CloudVault"; $env:AWS_PAGER=""
aws cognito-idp admin-delete-user --user-pool-id ap-southeast-2_WrrQjjWoG --username abhinavrag777+agent-owner@gmail.com
aws cognito-idp admin-delete-user --user-pool-id ap-southeast-2_WrrQjjWoG --username abhinavrag777+agent-recipient@gmail.com
Remove-Item .tmp\creds.json -Force
```

---

## 5. GitHub OIDC role creation (Phase 6 – CI/CD)

GitHub Actions needs an IAM role with an OIDC trust policy scoped to repo `IQnull7/CloudVault`. This is a one-time manual step:
1. In the AWS Console → IAM → Identity providers, add `token.actions.githubusercontent.com` as an OIDC provider (if not already present).
2. Create a role `CloudVault-GitHubActions-Role` with the trust policy limiting subject to `repo:IQnull7/CloudVault:*`.
3. Attach a permissions policy scoped to `CloudVault-*` resources only (Lambda, API Gateway, IAM for CloudVault roles, DynamoDB, S3 CloudVault bucket, Cognito CloudVault pool).

