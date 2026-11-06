#!/usr/bin/env pwsh
# plan-gate.ps1 – Parse terraform show -json tfplan and fail on dangerous actions.
# Run from the infrastructure/ directory AFTER "terraform plan -out=tfplan".
# Usage: scripts\plan-gate.ps1   (from repo root, it cds itself)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$infraDir = Join-Path $repoRoot "infrastructure"

Push-Location $infraDir
try {
    Write-Host "==> Running terraform show -json tfplan ..."
    $json = terraform show -json tfplan 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "terraform show -json failed. Run 'terraform plan -out=tfplan' first."
        exit 1
    }

    $plan = $json | ConvertFrom-Json

    # Protected resources – in-place updates are allowed, but delete/replace are not.
    $protected = @(
        "aws_s3_bucket.cloudvault",
        "aws_dynamodb_table.files",
        "aws_dynamodb_table.shares",
        "aws_dynamodb_table.audit_logs",
        "aws_cognito_user_pool.main",
        "aws_cognito_user_pool_client.web"
    )

    $failures = @()

    $changes = $plan.resource_changes
    if (-not $changes) {
        Write-Host "==> No resource changes in plan. Gate passed."
        exit 0
    }

    foreach ($rc in $changes) {
        $addr    = $rc.address
        $actions = $rc.change.actions

        # Fail on any delete or replace action on ANY resource.
        if ($actions -contains "delete" -or $actions -contains "replace") {
            $failures += "BLOCKED [$addr]: actions = $($actions -join ', ') (delete/replace not allowed)"
        }

        # Fail on update of specifically protected resources.
        if ($actions -contains "update") {
            foreach ($p in $protected) {
                if ($addr -eq $p) {
                    $failures += "BLOCKED [$addr]: in-place update of protected resource not allowed (actions = $($actions -join ', '))"
                }
            }
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host ""
        Write-Host "PLAN GATE FAILED:" -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host "  $f" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Fix the Terraform code and re-plan. Do NOT apply this plan." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "PLAN GATE PASSED." -ForegroundColor Green
    $creates = @($changes | Where-Object { $_.change.actions -contains "create" }).Count
    $updates = @($changes | Where-Object { $_.change.actions -contains "update" }).Count
    Write-Host "  Creates: $creates  |  In-place updates: $updates"
    Write-Host ""
    exit 0
}
finally {
    Pop-Location
}

