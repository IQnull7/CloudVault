# CloudVault: Secure Serverless Cloud-Based File Sharing Platform

[![CloudVault CI/CD](https://github.com/IQnull7/CloudVault/actions/workflows/ci.yml/badge.svg)](https://github.com/IQnull7/CloudVault/actions/workflows/ci.yml)
[![Terraform](https://img.shields.io/badge/IaC-Terraform_1.17+-623CE4.svg?logo=terraform)](https://www.terraform.io/)
[![AWS Serverless](https://img.shields.io/badge/AWS-Serverless-FF9900.svg?logo=amazon-aws)](https://aws.amazon.com/)
[![React Vite](https://img.shields.io/badge/Frontend-React_19_+_Vite-61DAFB.svg?logo=react)](https://vitejs.dev/)

**CloudVault** is a security-first, serverless cloud file storage and sharing platform built on Amazon Web Services (AWS) using Infrastructure as Code (Terraform). It enforces backend authorization, strict least-privilege IAM, end-to-end encryption, and append-only audit logging.

---

## 1. Architecture Overview

CloudVault is built on a 100% serverless, on-demand architecture within AWS Free Tier limits:

```
                            +-----------------------------------------+
                            |         React SPA (Vite / S3)           |
                            |       Cognito SRP Authentication        |
                            +--------------------+--------------------+
                                                 |
                                     (1) Auth    |  (2) API calls
                                  +--------------+--------------+
                                  |                             |
                                  v                             v
                       +--------------------+        +---------------------+
                       |   Amazon Cognito   |        | API Gateway HTTP API|
                       | User Pool & Client |        | (Cognito Authorizer)|
                       +--------------------+        +----------+----------+
                                                                |
                                             +------------------+------------------+
                                             |                  |                  |
                                             v                  v                  v
                                     +---------------+  +---------------+  +---------------+
                                     | upload-url /  |  |   access /    |  |  audit-log /  |
                                     | complete      |  | shared-with-me|  |  revoke-share |
                                     +-------+-------+  +-------+-------+  +-------+-------+
                                             |                  |                  |
                       +---------------------+                  |                  |
                       |                     |                  |                  |
                       v                     v                  v                  v
             +------------------+   +------------------------------------------------------+
             |  Private S3      |   |                  Amazon DynamoDB                     |
             |  Bucket (AES256, |   +-------------------+------------------+---------------+
             |  TLS-only deny,  |   | CloudVault-Files  | CloudVault-Shares| CloudVault-   |
             |  Public Blocked) |   | (owner-index GSI) | (recipient-index)| AuditLogs     |
             +------------------+   +-------------------+------------------+---------------+
```

### Core Components

| Layer | Service | Purpose |
|---|---|---|
| **Frontend** | React (Vite) | Single Page Application with Cognito SRP authentication |
| **Edge & CDN** | S3 + CloudFront (OAC) | Dedicated private static hosting bucket with HTTPS caching |
| **API** | API Gateway (HTTP API v2) | Lightweight REST endpoints with native Cognito JWT authorizer |
| **Compute** | AWS Lambda (Node.js 22, ARM64) | 8 dedicated least-privilege micro-functions sharing code archive |
| **Identity & Auth** | Amazon Cognito User Pool | SRP authentication, email verification, 12+ char password policy |
| **Storage** | Amazon S3 | Private files bucket with AES256 server-side encryption, versioning, TLS-only deny |
| **Database** | Amazon DynamoDB | `PAY_PER_REQUEST` on-demand tables with GSIs and TTL automatic expiration |
| **Notifications** | Amazon SES | Share notification emails (sandbox mode) |
| **Observability** | CloudWatch Logs | 7-day retention log groups per Lambda; no raw secrets logged |
| **Infrastructure** | Terraform 1.17+ | Fully reproducible IaC with remote S3 state backend and native lockfile |
| **CI/CD** | GitHub Actions | Automated syntax checks, frontend build, Terraform fmt/validate |

---

## 2. Security Model & Design Decisions

### 1. Identity & Claims Enforcement
- **Email is the sole user identifier**: lowercased consistently across all DynamoDB records and Lambda queries.
- **`getCaller(event)` validation gate**: API Gateway accepts tokens, but Lambda strictly verifies:
  - `claims.token_use === "id"` (rejects access tokens which lack `email`)
  - `claims.email_verified === "true"`
  - `claims.email` is present
- Client request bodies are **never trusted** for caller identity, ownership, file ID, S3 keys, or file size.

### 2. Two-Step Verified Upload
1. `POST /files/upload-url`:
   - Server generates a UUID `fileId` and sets `s3Key = uploads/<fileId>`.
   - Validates declared size (max 10 MB) and MIME type.
   - Saves a `status: "pending"` record in `CloudVault-Files` with a 10-minute expiry.
   - Generates a 300-second presigned S3 PUT URL with signed `Content-Type` and `Content-Length`.
2. Browser uploads directly to private S3.
3. `POST /files/{id}/complete`:
   - Recomputes the S3 key on the server (client only sends `fileId`).
   - Issues `HeadObject` to S3 to verify real byte size and MIME type match what was declared.
   - Updates record to active via conditional put and logs an immutable audit event.

### 3. Granular Access Control (Core Security Proof)
- Direct S3 access is blocked (public access block + TLS-only bucket policy).
- File access (`GET /files/{id}/access`) verifies:
  - If caller is owner: granted `download` disposition (`attachment`).
  - If caller is shared recipient: queries `CloudVault-Shares` for `fileId` + `recipientEmail`.
  - Expiration check: `expiresAt` is checked explicitly in code (handles DynamoDB asynchronous TTL delay).
  - If no share exists: returns **403 Forbidden** and logs a `denied` audit entry.
  - If granted: issues a short-lived (60-second) presigned GET URL with appropriate `ResponseContentDisposition` (`inline` for view, `attachment` for download).

### 4. Append-Only Audit Logging
- Audit table is immutable at application level: writing Lambdas get only `dynamodb:PutItem` with `ConditionExpression: attribute_not_exists(fileId) AND attribute_not_exists(sk)`.
- Sort key: `<13-digit ms timestamp>#<uuid>` for strict chronological sorting.
- Owner-only audit reading (`GET /files/{id}/audit`): non-owners receive 404 (avoids file enumeration).

---

## 3. Endpoints

All endpoints require `Authorization: Bearer <ID_TOKEN>`.

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/files/upload-url` | Generate presigned PUT URL and pending record |
| `POST` | `/files/{id}/complete` | Verify S3 object and finalize file metadata |
| `GET` | `/files` | List files owned by the authenticated caller |
| `GET` | `/files/shared` | List files shared with the caller (never exposes s3Key) |
| `POST` | `/files/{id}/share` | Share a file (`view` or `download`, optional expiry) |
| `DELETE` | `/files/{id}/share?recipientEmail=` | Revoke a share (owner only) |
| `GET` | `/files/{id}/access` | Authorized presigned GET URL (60-second TTL) |
| `GET` | `/files/{id}/audit` | View immutable audit history (owner only) |

---

## 4. DynamoDB Table Schemas

### `CloudVault-Files`
- **Partition Key:** `fileId` (String, UUID)
- **GSI `owner-index`:** PK `ownerEmail` (S), SK `createdAt` (N)
- **Attributes:** `ownerEmail`, `fileName`, `s3Key`, `sizeBytes`, `contentType`, `tags`, `createdAt`

### `CloudVault-Shares`
- **Partition Key:** `fileId` (String, UUID)
- **Sort Key:** `recipientEmail` (String)
- **GSI `recipient-index`:** PK `recipientEmail` (S), SK `fileId` (S)
- **TTL:** Enabled on `expiresAt` (epoch seconds)
- **Attributes:** `permission` (`view` | `download`), `sharedBy`, `sharedAt`, `expiresAt`

### `CloudVault-AuditLogs`
- **Partition Key:** `fileId` (String, UUID)
- **Sort Key:** `sk` (String: `<timestamp>#<uuid>`)
- **GSI `actor-index`:** PK `actorEmail` (S), SK `ts` (N)
- **Attributes:** `actorEmail`, `eventType` (`upload` | `download` | `share` | `view`), `outcome` (`success` | `denied` | `not_found`), `sourceIp`, `ts`, `targetEmail`, `detail`

---

## 5. Deployment Instructions

### Prerequisites
- AWS CLI configured with active profile (`$env:AWS_PROFILE = "CloudVault"`)
- Terraform >= 1.10 installed (tested on 1.17.1)
- Node.js >= 20, PowerShell 5.1+

### Deploy Infrastructure
```powershell
# 1. Set environment
$env:AWS_PROFILE = "CloudVault"
$env:AWS_PAGER = ""

# 2. Initialize Terraform with remote S3 backend
cd infrastructure
terraform init

# 3. Format and validate
terraform fmt -recursive
terraform validate

# 4. Plan with safety gate
terraform plan -out=tfplan
powershell -ExecutionPolicy Bypass -File ..\scripts\plan-gate.ps1

# 5. Apply
terraform apply tfplan
```

### Run Automated Security Test Suite
```powershell
# Runs 24 comprehensive security & integration tests
powershell -ExecutionPolicy Bypass -File scripts\e2e-test.ps1
```

### Run Frontend Locally
```powershell
cd frontend
npm install
npm run dev
# Open http://localhost:5173
```

---

## 6. Honest Limitations & Security Trade-offs

1. **View-only cannot prevent client capture:** Presigned URLs with `inline` disposition instruct browsers to render files in-tab instead of prompting a save dialogue. However, no web technology can prevent a determined recipient from capturing screenshots, printing, or inspecting browser memory.
2. **Presigned URL revocation window:** Amazon S3 presigned URLs are cryptographically signed tokens. Revoking a share immediately prevents *new* access URLs from being generated, but cannot invalidate an already-issued presigned URL during its 60-second validity window. Keeping URL expiration short (60 seconds) strictly bounds this exposure window.
3. **DynamoDB TTL asynchronous cleanup:** DynamoDB deletes expired items typically within 48 hours of expiration. Therefore, Lambdas perform explicit client-side timestamp checks (`share.expiresAt < now`) on every access request to ensure immediate enforcement.

---

## 7. AWS Free Tier Cost Guardrails

- **Lambda:** ARM64 Graviton2 architecture; 256 MB memory allocation; 10s execution timeout. Well within the 1M requests/month free tier.
- **DynamoDB:** `PAY_PER_REQUEST` (on-demand billing) across all 3 tables with no provisioned minimums.
- **S3:** Standard AES256 server-side encryption; versioning enabled; zero public egress fees through presigned direct uploads.
- **CloudWatch:** 7-day retention policy strictly enforced on every Lambda log group to prevent log accumulation costs.
