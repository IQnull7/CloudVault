# CloudVault Project Status

**Branch:** `agent-work`  
**Current Date:** 2026-11-07  
**AWS Account ID:** 373468206201  
**AWS Region:** ap-southeast-2 (Sydney)  
**Overall Completion:** 100% of planned deliverables (Phases 0 through 7 complete)

---

## 1. What is Deployed and Verified

| Component | Status | Details |
|---|---|---|
| **S3 Files Bucket** | Deployed & Hardened | `cloudvault-files-373468206201-ap-southeast-2`, AES256, versioning, public access blocked, CORS configured, TLS-only deny policy |
| **S3 Frontend Bucket** | Deployed & Populated | `cloudvault-frontend-373468206201-ap-southeast-2`, private, AES256, public blocked, OAC configured, synced with React bundle |
| **DynamoDB Tables** | Deployed & Verified | `CloudVault-Files` (owner-index GSI), `CloudVault-Shares` (recipient-index GSI, TTL), `CloudVault-AuditLogs` (actor-index GSI). All on-demand. |
| **Cognito User Pool & Client** | Deployed & Hardened | User Pool `ap-southeast-2_WrrQjjWoG`, Client `3ai5rj3p3h4eogpgq36qa8spe5`. Removed `ALLOW_USER_PASSWORD_AUTH`. SRP and Refresh Token auth only. |
| **HTTP API Gateway** | Deployed & Secured | Endpoint: `https://yt8eyqih2c.execute-api.ap-southeast-2.amazonaws.com` with native Cognito JWT authorizer (`CognitoJWT`) |
| **8 Lambda Functions** | Deployed & Verified | `CloudVault-upload-url`, `CloudVault-complete`, `CloudVault-list-files`, `CloudVault-share`, `CloudVault-access`, `CloudVault-revoke-share`, `CloudVault-shared-with-me`, `CloudVault-audit-log`. All nodejs22.x on arm64 with least-privilege IAM and 7-day log retention. |
| **SES Email Identity** | Deployed | Sender `abhinavrag777@gmail.com` registered in SES Sydney (sandbox). Share Lambda gracefully handles unverified status. |
| **Remote Terraform State** | Deployed & Active | S3 bucket `cloudvault-tfstate-373468206201-ap-southeast-2` with `use_lockfile = true` and AES256 encryption. |
| **Plan Gate Script** | Created & Verified | `scripts/plan-gate.ps1` safely enforces zero deletes/replaces and restricts updates. |
| **React Frontend** | Built & Deployed | React 19 + Vite SPA with Cognito SRP auth, direct S3 upload, file sharing, access control, and audit viewer. Synced to S3. |
| **CI/CD Workflow** | Created | `.github/workflows/ci.yml` validates Lambda syntax, builds frontend, checks Terraform fmt/validate. |

---

## 2. Test Results

Automated test suite (`scripts/e2e-test.ps1`) executed against live AWS infrastructure:
- **Total Tests:** 24
- **Passed:** 24 (100%)
- **Failed:** 0
- **Evidence:** Logged in `docs/TEST-EVIDENCE.md`

### Core Security Proofs Confirmed:
1. Unauthenticated requests to all endpoints return `401 Unauthorized`.
2. Access tokens (without `email` claim) return `401 Unauthorized`.
3. Non-owner / unauthorized users receive **`403 Forbidden`** on files before a share exists (core security proof).
4. View-shared files receive presigned GET URLs with `ResponseContentDisposition = inline`.
5. Download-shared and owner files receive presigned GET URLs with `ResponseContentDisposition = attachment`.
6. Expired shares (past `expiresAt`) return **`403 Forbidden`**.
7. Revoking a share immediately returns **`403 Forbidden`** on subsequent access requests.
8. File audit trail is readable only by the owner; non-owners receive `404 Not Found`.
9. `GET /files/shared` never exposes internal `s3Key`.

---

## 3. Human Actions Pending

See `docs/HUMAN-TODO.md` for full details:
1. **CloudFront Account Verification:** AWS Free Tier accounts require a support ticket to unlock CloudFront distribution creation. Once verified, flip `enable_cloudfront = true` in `infrastructure/variables.tf`.
2. **SES Sender Email Verification:** Click the verification link sent to `abhinavrag777@gmail.com` to enable live notification emails in sandbox mode.
3. **Browser Smoke Test:** Run `npm run dev` in `frontend/` to test UI in browser.
