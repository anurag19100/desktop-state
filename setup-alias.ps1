# setup-alias.ps1 — Run once to register desktop-state command
# Usage: & "C:\Users\anura\Documents\ws\setup-alias.ps1"

$scriptPath = 'C:\Users\anura\Documents\ws\desktop-state.ps1'

if (-not (Test-Path $scriptPath)) {
    Write-Host ''
    Write-Host '  ERROR: desktop-state.ps1 not found at:' -ForegroundColor Red
    Write-Host "  $scriptPath" -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
}

$aliasBlock = @'

# ── Desktop State Manager ──────────────────────────────────────
function desktop-state {
    param([Parameter(Position=0)][string]$Command = "help", [string]$File = "")
    & 'C:\Users\anura\Documents\ws\desktop-state.ps1' -Command $Command -File $File
}
function ds { desktop-state @args }
# ───────────────────────────────────────────────────────────────
'@

# Create profile if it does not exist
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    Write-Host '  Created PowerShell profile.' -ForegroundColor Cyan
}

$existing = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($existing -match 'Desktop State Manager') {
    Write-Host ''
    Write-Host '  Alias already exists — no changes needed.' -ForegroundColor Green
} else {
    Add-Content -Path $PROFILE -Value $aliasBlock
    Write-Host ''
    Write-Host '  Alias added to profile successfully!' -ForegroundColor Green
}

Write-Host ''
Write-Host '  Now run this to activate it in the current window:' -ForegroundColor Yellow
Write-Host '  . $PROFILE' -ForegroundColor White
Write-Host ''
Write-Host '  Then use:' -ForegroundColor Cyan
Write-Host '  desktop-state help' -ForegroundColor White
Write-Host '  desktop-state snapshot' -ForegroundColor White
Write-Host '  desktop-state list' -ForegroundColor White
Write-Host '  desktop-state restore' -ForegroundColor White
Write-Host '  desktop-state delete' -ForegroundColor White
Write-Host ''
Read-Host 'Press Enter to close'
