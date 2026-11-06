# CloudVault – Architecture & Design Decisions

Recorded by the autonomous agent. Decisions are made to resolve ambiguity; none contradict the HANDOVER.md design decisions.

---

## D-001: s3Key omitted from sharedWithMe response

**Decision:** `GET /files/shared` returns `fileId, fileName, sizeBytes, contentType, createdAt, permission, sharedBy, expiresAt` and never `s3Key`.  
**Reason:** The S3 key is an internal server detail. Exposing it to a recipient would let them construct guesses at other keys and would leak the storage layout. The access URL is obtained only via `GET /files/{id}/access`, which enforces the permission check.

---

## D-002: writeAudit swallows errors

**Decision:** The shared `audit.js` helper catches and CloudWatch-logs any DynamoDB error rather than re-throwing it.  
**Reason:** An audit write failure must never cause the main operation (upload, share, access) to fail. The alternative — a transaction — costs 2× read/write capacity and doesn't fit with PutItem-only IAM.

---

## D-003: Revoke is idempotent

**Decision:** `DELETE /files/{id}/share` calls `DeleteItem` without a ConditionExpression, so it succeeds even if the share doesn't exist.  
**Reason:** Idempotent DELETE is the standard REST convention. The caller only needs to know the share is gone; a 404 for a non-existent share would force the UI to handle an unnecessary error case.

---

## D-004: SES send failure does not fail the share

**Decision:** The share Lambda catches SES errors and logs them to CloudWatch, then returns HTTP 200 anyway.  
**Reason:** Per HANDOVER.md Phase 2 spec. The share record is already written; the email is a notification, not a gate.

---

## D-005: AWS_SES_REGION env var named carefully

**Decision:** The env var that holds the SES region is named `AWS_SES_REGION` (not `AWS_REGION`).  
**Reason:** `AWS_REGION` is injected by Lambda automatically. Overriding it would break all AWS SDK clients. Using a custom name avoids the collision while still letting the share Lambda point SES at `ap-southeast-2`.

---

## D-006: plan-gate.ps1 blocks delete/replace on all resources, in-place updates on protected resources only

**Decision:** The gate blocks any `delete` or `replace` action on any resource; it blocks `update` only on the six protected resources (S3 bucket, 3 DynamoDB tables, Cognito pool and client).  
**Reason:** Lambda code-hash updates (`update` on `aws_lambda_function.*`) and API Gateway route changes are routine and must be allowed; the handover explicitly sanctions them. Deletes and replaces are never expected during normal work.

---

## D-007: Backend package zip includes all src/* files

**Decision:** `data.archive_file.backend` zips the entire `backend/` directory (src + package.json + node_modules). All Lambda functions share one zip and reference their own handler path.  
**Reason:** This keeps Terraform simple (one `source_code_hash`, all Lambdas update together) and avoids per-function zips. The zip is excluded from git via `.gitignore`.

