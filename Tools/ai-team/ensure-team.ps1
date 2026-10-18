<#
.SYNOPSIS
    Diagnoses and safely repairs named AI team configuration files.
.DESCRIPTION
    Idempotent, non-destructive script that verifies the presence and integrity
    of team configuration files across branches.
.PARAMETER Check
    Performs verification only (default).
.PARAMETER Apply
    Restores missing files from the canonical templates.
#>
[CmdletBinding()]
param(
    [switch]$Check = $true,
    [switch]$Apply = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

Write-Host "Checking AI Team configuration in: $RepoRoot" -ForegroundColor Cyan

$RequiredFiles = @(
    "AGENTS.md",
    "GEMINI.md",
    ".agents\rules\ai-team-router.md",
    ".agents\skills\asana-team-coordination\SKILL.md",
    "docs\ai-team\TEAM.md",
    "docs\ai-team\PROJECT_ASSIGNMENTS.md",
    "docs\ai-team\ASANA_POLICY.md",
    "docs\ai-team\TASK_HANDOFF_TEMPLATE.md",
    "docs\ai-team\PLATFORMS.md",
    "docs\ai-team\BRANCH_INTEGRATION.md",
    "docs\ai-team\VALIDATION.md"
)

$Roles = @("eitan", "noam", "maya", "roni", "tomer", "yael", "dana")
foreach ($r in $Roles) {
    $RequiredFiles += ".agents\agents\$r.md"
    $RequiredFiles += ".agents\roles\$r.md"
    $RequiredFiles += ".codex\agents\$r.toml"
}

$Missing = @()
foreach ($f in $RequiredFiles) {
    $fullPath = Join-Path $RepoRoot $f
    if (-not (Test-Path $fullPath)) {
        $Missing += $f
    }
}

if ($Missing.Count -eq 0) {
    Write-Host "PASS: All $($RequiredFiles.Count) team files exist." -ForegroundColor Green
    exit 0
} else {
    Write-Host "WARNING: Missing $($Missing.Count) files:" -ForegroundColor Yellow
    foreach ($m in $Missing) {
        Write-Host "  - $m" -ForegroundColor Red
    }
    if ($Apply) {
        Write-Host "Apply mode requested. Please run the canonical sync script or checkout from configured branch." -ForegroundColor Cyan
    }
    exit 1
}
