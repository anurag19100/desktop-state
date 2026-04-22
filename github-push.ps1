# github-push.ps1
# Creates the GitHub repo and pushes desktop-state to it.
# Run from: C:\Users\anura\Documents\ws\desktop-state\

$repoDir  = 'C:\Users\anura\Documents\ws\desktop-state'
$repoName = 'desktop-state'
$desc     = 'Windows desktop session manager - snapshot, restore, list and delete virtual desktop states'

Set-Location $repoDir

Write-Host ''
Write-Host '  =================================' -ForegroundColor Cyan
Write-Host '    GitHub Push - desktop-state   ' -ForegroundColor Cyan
Write-Host '  =================================' -ForegroundColor Cyan
Write-Host ''

# ── Make sure git repo exists ─────────────────────────────────────────────────
if (-not (Test-Path '.git')) {
    Write-Host '  No git repo found. Initialising...' -ForegroundColor Yellow
    git init -b main
    git config user.name  'Rocky'
    git config user.email 'anurag19100@gmail.com'
    git add .
    git commit -m 'feat: initial commit - desktop-state v1.1'
}

# ── Try GitHub CLI first ──────────────────────────────────────────────────────
$ghAvailable = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)

if ($ghAvailable) {
    Write-Host '  GitHub CLI (gh) detected.' -ForegroundColor Green
    Write-Host ''

    # Check auth
    $authStatus = gh auth status 2>&1
    if ($authStatus -match 'not logged') {
        Write-Host '  Logging in to GitHub...' -ForegroundColor Yellow
        gh auth login
    }

    Write-Host '  Creating GitHub repo...' -ForegroundColor Cyan
    gh repo create $repoName --public --description $desc --source . --remote origin --push

    Write-Host ''
    Write-Host '  Done!' -ForegroundColor Green
    $remoteUrl = git remote get-url origin
    Write-Host "  Repo: $remoteUrl" -ForegroundColor White

} else {
    # ── Manual fallback ───────────────────────────────────────────────────────
    Write-Host '  GitHub CLI (gh) not found. Using manual git push.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Step 1: Go to https://github.com/new and create a repo named:' -ForegroundColor Cyan
    Write-Host "          $repoName" -ForegroundColor White
    Write-Host '          (set to Public, no README, no .gitignore)' -ForegroundColor DarkGray
    Write-Host ''
    $username = Read-Host '  Step 2: Enter your GitHub username'
    $remoteUrl = "https://github.com/$username/$repoName.git"

    Write-Host ''
    Write-Host "  Adding remote: $remoteUrl" -ForegroundColor Cyan
    git remote remove origin 2>$null
    git remote add origin $remoteUrl

    Write-Host '  Pushing to GitHub...' -ForegroundColor Cyan
    git push -u origin main

    Write-Host ''
    Write-Host '  Done!' -ForegroundColor Green
    Write-Host "  Repo: https://github.com/$username/$repoName" -ForegroundColor White
}

Write-Host ''
Read-Host 'Press Enter to close'
