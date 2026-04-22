# git-init.ps1 — Run once to initialise the git repo
# Right-click -> Run with PowerShell

$repoDir = 'C:\Users\anura\Documents\ws\desktop-state'
Set-Location $repoDir

# Remove any broken .git from previous attempt
if (Test-Path '.git') {
    Remove-Item -Recurse -Force '.git'
    Write-Host '  Cleaned up old .git folder.' -ForegroundColor DarkGray
}

# Check git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  ERROR: git not found.' -ForegroundColor Red
    Write-Host '  Install from: https://git-scm.com/download/win' -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
}

Write-Host ''
Write-Host '  Initialising git repo...' -ForegroundColor Cyan

git init -b main
git config user.name  'Rocky'
git config user.email 'anurag19100@gmail.com'
git add .
git commit -m 'feat: initial commit - desktop-state v1.1'

Write-Host ''
Write-Host '  Done! Repo structure:' -ForegroundColor Green
git log --oneline
Write-Host ''
git status
Write-Host ''
Read-Host 'Press Enter to close'
