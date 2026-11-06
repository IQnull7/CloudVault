#!/usr/bin/env pwsh
# e2e-test.ps1 – Full end-to-end security and functional test for CloudVault backend.
# Run from the repo root: scripts\e2e-test.ps1
# Requires: AWS_PROFILE=CloudVault, PowerShell 5.1+, creds in .tmp\creds.json

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Config ───────────────────────────────────────────────────────────────────
$API         = "https://yt8eyqih2c.execute-api.ap-southeast-2.amazonaws.com"
$POOL_ID     = "ap-southeast-2_WrrQjjWoG"
$CLIENT_ID   = "3ai5rj3p3h4eogpgq36qa8spe5"
$REGION      = "ap-southeast-2"
$SHARES_TABLE = "CloudVault-Shares"

$creds = Get-Content ".tmp\creds.json" | ConvertFrom-Json
$OWNER_EMAIL     = $creds.owner
$RECIPIENT_EMAIL = $creds.recipient
$PASSWORD        = $creds.password

$results = [System.Collections.ArrayList]@()
$PASS = 0; $FAIL = 0

function Record($name, $pass, $detail = "") {
    $status = if ($pass) { "PASS" } else { "FAIL" }
    if ($pass) { $script:PASS++ } else { $script:FAIL++ }
    $script:results.Add([PSCustomObject]@{ Test=$name; Result=$status; Detail=$detail }) | Out-Null
    $color = if ($pass) { "Green" } else { "Red" }
    Write-Host "[$status] $name" -ForegroundColor $color
    if ($detail) { Write-Host "       $detail" }
}

function GetIdToken($email, $pwd) {
    $authBody = @{
        AuthFlow       = "USER_PASSWORD_AUTH"
        ClientId       = $CLIENT_ID
        AuthParameters = @{ USERNAME = $email; PASSWORD = $pwd }
    } | ConvertTo-Json
    $authBody | Set-Content -Encoding ascii ".tmp\auth_req.json"
    $resp = aws cognito-idp initiate-auth --cli-input-json file://.tmp/auth_req.json | ConvertFrom-Json
    return $resp.AuthenticationResult.IdToken
}

function Invoke($method, $path, $token = $null, $body = $null) {
    $uri = "$API$path"
    $headers = @{ "Content-Type" = "application/json" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    try {
        $params = @{ Uri=$uri; Method=$method; Headers=$headers; UseBasicParsing=$true }
        if ($body) { $params["Body"] = ($body | ConvertTo-Json) }
        $r = Invoke-WebRequest @params
        return @{ status=[int]$r.StatusCode; body=($r.Content | ConvertFrom-Json) }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $stream = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $text   = $reader.ReadToEnd()
            try { $json = $text | ConvertFrom-Json } catch { $json = @{ raw = $text } }
            return @{ status=[int]$resp.StatusCode; body=$json }
        }
        return @{ status=0; body=@{ error=$_.Exception.Message } }
    }
}

Write-Host ""
Write-Host "===== CloudVault E2E Test =====" -ForegroundColor Cyan
Write-Host ""

# ── 1. Unauthenticated → 401 ─────────────────────────────────────────────────
Write-Host "-- Auth checks --"
$r = Invoke "GET" "/files"
Record "No-token GET /files → 401" ($r.status -eq 401) "HTTP $($r.status)"

$r = Invoke "GET" "/files/00000000-0000-0000-0000-000000000001/access"
Record "No-token GET /access → 401" ($r.status -eq 401) "HTTP $($r.status)"

# ── 2. Get tokens ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "-- Getting tokens --"
$ownerToken     = GetIdToken $OWNER_EMAIL $PASSWORD
$recipientToken = GetIdToken $RECIPIENT_EMAIL $PASSWORD
Write-Host "Tokens obtained."

# Access token (not ID token) → 401 from getCaller
$accessTokenBody = @{
    AuthFlow       = "USER_PASSWORD_AUTH"
    ClientId       = $CLIENT_ID
    AuthParameters = @{ USERNAME = $OWNER_EMAIL; PASSWORD = $PASSWORD }
} | ConvertTo-Json
$accessTokenBody | Set-Content -Encoding ascii ".tmp\auth_access.json"
$accessTokenResp = aws cognito-idp initiate-auth --cli-input-json file://.tmp/auth_access.json | ConvertFrom-Json
$accessToken = $accessTokenResp.AuthenticationResult.AccessToken

$r = Invoke "GET" "/files" $accessToken
Record "Access-token (not ID) GET /files → 401" ($r.status -eq 401) "HTTP $($r.status) (getCaller rejects non-ID token)"

# ── 3. Upload a test file as owner ───────────────────────────────────────────
Write-Host ""
Write-Host "-- Upload flow (owner) --"
$uploadReq = @{ fileName="test.txt"; sizeBytes=12; contentType="text/plain" }
$r = Invoke "POST" "/files/upload-url" $ownerToken $uploadReq
Record "POST /files/upload-url → 200" ($r.status -eq 200) "HTTP $($r.status)"
$fileId  = $r.body.fileId
$uploadUrl = $r.body.uploadUrl

# PUT to S3 presigned URL
try {
    "hello world!" | Set-Content -Encoding ascii ".tmp\testfile.txt" -NoNewline
    $putHeaders = @{ "Content-Type" = "text/plain" }
    Invoke-WebRequest -Uri $uploadUrl -Method PUT -InFile ".tmp\testfile.txt" -Headers $putHeaders -UseBasicParsing | Out-Null
    Record "Direct S3 PUT upload → success" $true "fileId=$fileId"
} catch {
    Record "Direct S3 PUT upload → success" $false "$_"
}

# Complete the upload
$r = Invoke "POST" "/files/$fileId/complete" $ownerToken
Record "POST /files/{id}/complete → 200" ($r.status -eq 200) "HTTP $($r.status)"

# ── 4. List files ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "-- List files --"
$r = Invoke "GET" "/files" $ownerToken
Record "GET /files → 200 with file" ($r.status -eq 200 -and ($r.body.files | Where-Object { $_.fileId -eq $fileId })) "HTTP $($r.status), count=$($r.body.files.Count)"

# ── 5. Recipient gets 403 BEFORE share ───────────────────────────────────────
Write-Host ""
Write-Host "-- Access control (the core proof) --"
$r = Invoke "GET" "/files/$fileId/access" $recipientToken
Record "Recipient GET /access BEFORE share → 403" ($r.status -eq 403) "HTTP $($r.status) [CORE SECURITY TEST]"

# ── 6. Owner shares as 'view' ─────────────────────────────────────────────────
Write-Host ""
Write-Host "-- Share --"
$shareBody = @{ recipientEmail=$RECIPIENT_EMAIL; permission="view" }
$r = Invoke "POST" "/files/$fileId/share" $ownerToken $shareBody
Record "POST /files/{id}/share (view) → 200" ($r.status -eq 200) "HTTP $($r.status)"

# ── 7. Recipient gets URL AFTER share ─────────────────────────────────────────
$r = Invoke "GET" "/files/$fileId/access" $recipientToken
Record "Recipient GET /access AFTER share → 200" ($r.status -eq 200) "HTTP $($r.status)"
$viewUrl = $r.body.url

# Check inline disposition
$viewUrlOk = $viewUrl -and ($viewUrl -match "response-content-disposition=inline")
Record "View URL has inline disposition" $viewUrlOk "disposition in URL: $viewUrlOk"

# Download the content and verify
try {
    $content = (Invoke-WebRequest -Uri $viewUrl -UseBasicParsing).Content
    Record "View URL returns file content" ($content.Trim() -eq "hello world!") "got: $content"
} catch {
    Record "View URL returns file content" $false "$_"
}

# ── 8. Owner gets download disposition ────────────────────────────────────────
$r = Invoke "GET" "/files/$fileId/access" $ownerToken
$ownerUrl = $r.body.url
$attachOk = $ownerUrl -and ($ownerUrl -match "response-content-disposition=attachment")
Record "Owner GET /access has attachment disposition" $attachOk "HTTP $($r.status)"

# ── 9. Expired share is denied ─────────────────────────────────────────────────
Write-Host ""
Write-Host "-- Expired share --"
# Put a share with expiresAt in the past directly via CLI
$pastExpiry  = [int][Math]::Floor((Get-Date).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalSeconds) - 3600
$expShareJson = @{
    Item = @{
        fileId        = @{ S = $fileId }
        recipientEmail = @{ S = "abhinavrag777+agent-other@gmail.com" }
        permission    = @{ S = "download" }
        sharedBy      = @{ S = $OWNER_EMAIL }
        sharedAt      = @{ N = "0" }
        expiresAt     = @{ N = "$pastExpiry" }
    }
    TableName = $SHARES_TABLE
} | ConvertTo-Json -Depth 10
$expShareJson | Set-Content -Encoding ascii ".tmp\expired_share.json"
aws dynamodb put-item --cli-input-json file://.tmp/expired_share.json 2>&1 | Out-Null

# We can't log in as that email (not a real Cognito user), so test the explicit
# expiry logic by temporarily updating the REAL recipient's share to be expired.
$expShareJson2 = @{
    Item = @{
        fileId        = @{ S = $fileId }
        recipientEmail = @{ S = $RECIPIENT_EMAIL }
        permission    = @{ S = "view" }
        sharedBy      = @{ S = $OWNER_EMAIL }
        sharedAt      = @{ N = "0" }
        expiresAt     = @{ N = "$pastExpiry" }
    }
    TableName = $SHARES_TABLE
} | ConvertTo-Json -Depth 10
$expShareJson2 | Set-Content -Encoding ascii ".tmp\expired_share2.json"
aws dynamodb put-item --cli-input-json file://.tmp/expired_share2.json 2>&1 | Out-Null

$r = Invoke "GET" "/files/$fileId/access" $recipientToken
Record "Expired share → 403" ($r.status -eq 403) "HTTP $($r.status) expiresAt=$pastExpiry"

# Restore the valid share (no expiry)
$validShareJson = @{
    Item = @{
        fileId        = @{ S = $fileId }
        recipientEmail = @{ S = $RECIPIENT_EMAIL }
        permission    = @{ S = "view" }
        sharedBy      = @{ S = $OWNER_EMAIL }
        sharedAt      = @{ N = "0" }
    }
    TableName = $SHARES_TABLE
} | ConvertTo-Json -Depth 10
$validShareJson | Set-Content -Encoding ascii ".tmp\valid_share.json"
aws dynamodb put-item --cli-input-json file://.tmp/valid_share.json 2>&1 | Out-Null

# ── 10. GET /files/shared (recipient) ──────────────────────────────────────────
Write-Host ""
Write-Host "-- Shared-with-me list --"
$r = Invoke "GET" "/files/shared" $recipientToken
$sharedEntry = $r.body.files | Where-Object { $_.fileId -eq $fileId }
Record "GET /files/shared → 200 with entry" ($r.status -eq 200 -and $sharedEntry) "HTTP $($r.status)"
# Check s3Key absence without triggering StrictMode property-not-found error.
$sharedEntryProps = if ($sharedEntry) { ($sharedEntry | Get-Member -MemberType NoteProperty).Name } else { @() }
$noS3Key = $sharedEntryProps -notcontains "s3Key"
Record "Shared-with-me response has no s3Key" $noS3Key "s3Key in response: $(-not $noS3Key)"

# ── 11. Revoke share → recipient gets 403 ──────────────────────────────────────
Write-Host ""
Write-Host "-- Revoke share --"
$revokeUri = "$API/files/$fileId/share?recipientEmail=$([Uri]::EscapeDataString($RECIPIENT_EMAIL))"
$revokeHeaders = @{ "Content-Type" = "application/json"; "Authorization" = "Bearer $ownerToken" }
try {
    $revokeResp = Invoke-WebRequest -Uri $revokeUri -Method DELETE -Headers $revokeHeaders -UseBasicParsing
    $revokeStatus = [int]$revokeResp.StatusCode
} catch {
    $errResp = $_.Exception.Response
    $revokeStatus = if ($errResp) { [int]$errResp.StatusCode } else { 0 }
}
Record "DELETE /files/{id}/share → 200" ($revokeStatus -eq 200) "HTTP $revokeStatus"

$r = Invoke "GET" "/files/$fileId/access" $recipientToken
Record "Recipient GET /access after revoke → 403" ($r.status -eq 403) "HTTP $($r.status)"

# ── 12. Audit log (owner reads, sees all events) ───────────────────────────────
Write-Host ""
Write-Host "-- Audit log --"
$r = Invoke "GET" "/files/$fileId/audit" $ownerToken
$events = $r.body.events
Record "GET /files/{id}/audit → 200" ($r.status -eq 200) "HTTP $($r.status)"
$hasUpload  = $events | Where-Object { $_.eventType -eq "upload"  -and $_.outcome -eq "success" }
$hasDenied  = $events | Where-Object { $_.outcome -eq "denied" }
$hasShare   = $events | Where-Object { $_.eventType -eq "share"   -and $_.outcome -eq "success" }
$hasRevoke  = $events | Where-Object { $_.eventType -eq "share"   -and ($_.PSObject.Properties["detail"]) -and $_.detail -eq "revoke" }
Record "Audit has upload/success" ([bool]$hasUpload) ""
Record "Audit has at least one denied event" ([bool]$hasDenied) ""
Record "Audit has share/success" ([bool]$hasShare) ""
Record "Audit has revoke event" ([bool]$hasRevoke) ""

# ── 13. Recipient cannot read audit log ────────────────────────────────────────
$r = Invoke "GET" "/files/$fileId/audit" $recipientToken
Record "Recipient GET /audit → 404 (not owner)" ($r.status -eq 404) "HTTP $($r.status)"

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "===== RESULTS =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Write-Host ""
if ($FAIL -eq 0) {
    Write-Host "ALL $PASS TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "$PASS PASSED / $FAIL FAILED" -ForegroundColor Red
}

# Write to docs/TEST-EVIDENCE.md
$md = @"
# CloudVault Backend – Test Evidence

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") UTC
API: $API

## Results

| Test | Result | Detail |
|------|--------|--------|
"@
foreach ($row in $results) {
    $emoji = if ($row.Result -eq "PASS") { "✅" } else { "❌" }
    $md += "`n| $emoji $($row.Test) | $($row.Result) | $($row.Detail) |"
}
$md += @"

## Summary

- **Passed:** $PASS
- **Failed:** $FAIL

## Security Properties Verified

- Unauthenticated requests return 401
- Access tokens (non-ID) return 401 (getCaller rejects token_use != "id")
- User B (recipient) gets **403** on User A's file **before** a share exists
- After a view-share: User B gets a URL with `inline` content-disposition
- Owner always gets `attachment` content-disposition
- Expired shares (expiresAt in the past) return 403
- After revoke: User B gets **403** again
- Audit log is readable only by the file owner (recipient gets 404)
- Shared-with-me response never includes s3Key

## Limitations (by design)

- View-only cannot prevent screenshots or copy-paste
- Revoking a share cannot invalidate an already-issued 60-second presigned URL
"@

New-Item -ItemType Directory -Force "docs" | Out-Null
$md | Set-Content -Encoding utf8 "docs\TEST-EVIDENCE.md"
Write-Host ""
Write-Host "Test evidence written to docs/TEST-EVIDENCE.md"

if ($FAIL -gt 0) { exit 1 } else { exit 0 }
