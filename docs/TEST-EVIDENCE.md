# CloudVault Backend â€“ Test Evidence

Generated: 2026-11-07 01:24:16 UTC
API: https://yt8eyqih2c.execute-api.ap-southeast-2.amazonaws.com

## Results

| Test | Result | Detail |
|------|--------|--------|
| âœ… No-token GET /files â†’ 401 | PASS | HTTP 401 |
| âœ… No-token GET /access â†’ 401 | PASS | HTTP 401 |
| âœ… Access-token (not ID) GET /files â†’ 401 | PASS | HTTP 401 (getCaller rejects non-ID token) |
| âœ… POST /files/upload-url â†’ 200 | PASS | HTTP 200 |
| âœ… Direct S3 PUT upload â†’ success | PASS | fileId=2ea30435-2812-49d0-9e1e-532789b32a0f |
| âœ… POST /files/{id}/complete â†’ 200 | PASS | HTTP 200 |
| âœ… GET /files â†’ 200 with file | PASS | HTTP 200, count=4 |
| âœ… Recipient GET /access BEFORE share â†’ 403 | PASS | HTTP 403 [CORE SECURITY TEST] |
| âœ… POST /files/{id}/share (view) â†’ 200 | PASS | HTTP 200 |
| âœ… Recipient GET /access AFTER share â†’ 200 | PASS | HTTP 200 |
| âœ… View URL has inline disposition | PASS | disposition in URL: True |
| âœ… View URL returns file content | PASS | got: hello world! |
| âœ… Owner GET /access has attachment disposition | PASS | HTTP 200 |
| âœ… Expired share â†’ 403 | PASS | HTTP 403 expiresAt=1793991241 |
| âœ… GET /files/shared â†’ 200 with entry | PASS | HTTP 200 |
| âœ… Shared-with-me response has no s3Key | PASS | s3Key in response: False |
| âœ… DELETE /files/{id}/share â†’ 200 | PASS | HTTP 200 |
| âœ… Recipient GET /access after revoke â†’ 403 | PASS | HTTP 403 |
| âœ… GET /files/{id}/audit â†’ 200 | PASS | HTTP 200 |
| âœ… Audit has upload/success | PASS |  |
| âœ… Audit has at least one denied event | PASS |  |
| âœ… Audit has share/success | PASS |  |
| âœ… Audit has revoke event | PASS |  |
| âœ… Recipient GET /audit â†’ 404 (not owner) | PASS | HTTP 404 |
## Summary

- **Passed:** 24
- **Failed:** 0

## Security Properties Verified

- Unauthenticated requests return 401
- Access tokens (non-ID) return 401 (getCaller rejects token_use != "id")
- User B (recipient) gets **403** on User A's file **before** a share exists
- After a view-share: User B gets a URL with inline content-disposition
- Owner always gets ttachment content-disposition
- Expired shares (expiresAt in the past) return 403
- After revoke: User B gets **403** again
- Audit log is readable only by the file owner (recipient gets 404)
- Shared-with-me response never includes s3Key

## Limitations (by design)

- View-only cannot prevent screenshots or copy-paste
- Revoking a share cannot invalidate an already-issued 60-second presigned URL
