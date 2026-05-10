# Desktop-State Virtual Desktop Restore Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `ds restore` so apps relaunch on their correct Windows 11 virtual desktop using launch-in-place (Switch-Desktop before launch) instead of the broken Move-Window approach.

**Architecture:** Switch the active virtual desktop before launching each group of apps for that desktop. Apps always open on the currently active desktop — no post-launch window moving needed. Removes `Move-ToDesktop` and `Wait-ForWindow` entirely.

**Tech Stack:** PowerShell 5.1, VirtualDesktop module ≥2.x (Win11 compatible), Win32 `user32.dll` via Add-Type.

---

## File Map

| File | Action | What changes |
|---|---|---|
| `desktop-state.ps1` | Modify | Module version guard, new `Invoke-Restore`, delete `Move-ToDesktop` + `Wait-ForWindow` |

---

### Task 1: Module Version Guard

**Files:**
- Modify: `desktop-state.ps1:22-33` (VD module init block)

- [ ] **Step 1: Open `desktop-state.ps1` and locate the VD module block (lines 22-33)**

Current code:
```powershell
$vdAvailable = $false
try {
    if (-not (Get-Module -ListAvailable -Name VirtualDesktop)) {
        Write-Host '  Installing VirtualDesktop module (one-time)...' -ForegroundColor Yellow
        Install-Module VirtualDesktop -Scope CurrentUser -Force -ErrorAction Stop
    }
    Import-Module VirtualDesktop -ErrorAction Stop
    $vdAvailable = $true
} catch {
    # Silent fallback - desktop placement will be skipped
}
```

- [ ] **Step 2: Replace with version-guarded block**

```powershell
$vdAvailable = $false
try {
    $installed = Get-Module -ListAvailable -Name VirtualDesktop | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $installed -or $installed.Version.Major -lt 2) {
        Write-Host '  Installing VirtualDesktop module (Win11 compatible)...' -ForegroundColor Yellow
        Install-Module VirtualDesktop -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module VirtualDesktop -ErrorAction Stop
    $vdAvailable = $true
} catch {
    # Silent fallback - desktop placement will be skipped
}
```

- [ ] **Step 3: Verify module loads correctly**

Run in a fresh PowerShell window:
```powershell
& 'C:\Users\anura\Documents\ws\desktop-state\desktop-state.ps1' help
```
Expected: banner prints, no red errors. If module was already ≥2.x, no install message. If <2.x, install message then banner.

- [ ] **Step 4: Commit**

```powershell
cd C:\Users\anura\Documents\ws\desktop-state
git add desktop-state.ps1
git commit -m "fix: upgrade VirtualDesktop module guard to require v2.x for Win11"
```

---

### Task 2: Remove Move-ToDesktop and Wait-ForWindow

**Files:**
- Modify: `desktop-state.ps1:89-116` (two functions to delete)

- [ ] **Step 1: Delete `Wait-ForWindow` function (lines 89-101)**

Remove this entire block:
```powershell
# Wait for a process to get a visible window, then return the process
function Wait-ForWindow {
    param([string]$ProcessName, [int]$TimeoutSec = 12)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
             Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 500
    }
    return $null
}
```

- [ ] **Step 2: Delete `Move-ToDesktop` function (lines 103-116)**

Remove this entire block:
```powershell
# Move a process window to a virtual desktop by index
function Move-ToDesktop {
    param($process, [int]$desktopIndex)
    if (-not $vdAvailable -or $desktopIndex -lt 0) { return }
    try {
        $count = Get-DesktopCount
        # Create extra desktops if needed
        while ((Get-DesktopCount) -le $desktopIndex) {
            New-Desktop | Out-Null
        }
        $target = Get-Desktop $desktopIndex
        Move-Window $target $process | Out-Null
    } catch {}
}
```

- [ ] **Step 3: Verify script still loads**

```powershell
& 'C:\Users\anura\Documents\ws\desktop-state\desktop-state.ps1' help
```
Expected: banner + help text, no errors about missing functions.

- [ ] **Step 4: Commit**

```powershell
cd C:\Users\anura\Documents\ws\desktop-state
git add desktop-state.ps1
git commit -m "refactor: remove Move-ToDesktop and Wait-ForWindow (replaced by launch-in-place)"
```

---

### Task 3: Rewrite Invoke-Restore with Launch-in-Place

**Files:**
- Modify: `desktop-state.ps1` — `Invoke-Restore` function (lines 198-307)

- [ ] **Step 1: Replace the entire `Invoke-Restore` function**

Find the function from `function Invoke-Restore {` to its closing `}` (currently lines 198-307) and replace with:

```powershell
# ── RESTORE ───────────────────────────────────────────────────────────────────
function Invoke-Restore {
    param([string]$JsonFile)

    if ($JsonFile -eq '') {
        $snaps = Get-Snapshots
        if ($snaps.Count -eq 0) {
            Write-Host '  No snapshots found. Run: ds snapshot' -ForegroundColor Red
            return
        }
        $JsonFile = $snaps[0].FullName
        Write-Host "  Using latest: $($snaps[0].Name)" -ForegroundColor Cyan
        Write-Host ''
    }

    if (-not (Test-Path $JsonFile)) {
        Write-Host "  File not found: $JsonFile" -ForegroundColor Red
        return
    }

    $data = Get-Content $JsonFile -Encoding UTF8 | ConvertFrom-Json
    Write-Host "  Snapshot   : $($data.SavedAt)" -ForegroundColor White
    Write-Host "  Windows    : $($data.WindowCount)" -ForegroundColor White
    if ($vdAvailable) {
        Write-Host '  VD support : ON - apps will switch to correct desktops' -ForegroundColor Green
    } else {
        Write-Host '  VD support : OFF - install VirtualDesktop module v2+' -ForegroundColor Yellow
    }
    Write-Host ''

    $skip = @('explorer','SearchHost','StartMenuExperienceHost','ShellExperienceHost',
               'TextInputHost','SystemSettings','ApplicationFrameHost','ctfmon',
               'dwm','csrss','winlogon','taskhostw','sihost','fontdrvhost','lsass','svchost')

    $launched = 0; $skipped = 0; $failed = 0

    # Pre-create all required virtual desktops up-front
    if ($vdAvailable) {
        $maxVd = ($data.Windows | Where-Object { $_.VirtualDesktop -ge 0 } | Measure-Object -Property VirtualDesktop -Maximum).Maximum
        if ($null -ne $maxVd) {
            while ((Get-DesktopCount) -le $maxVd) {
                New-Desktop | Out-Null
            }
        }
    }

    # Group windows by virtual desktop index, unknowns (-1) go to group -1
    $groups = $data.Windows | Group-Object -Property VirtualDesktop | Sort-Object { [int]$_.Name }

    foreach ($group in $groups) {
        $vdIdx = [int]$group.Name

        # Switch to target desktop before launching this group
        if ($vdAvailable -and $vdIdx -ge 0) {
            try {
                Switch-Desktop (Get-Desktop $vdIdx)
                Start-Sleep -Milliseconds 300
                Write-Host "  -- Desktop $($vdIdx + 1) --" -ForegroundColor DarkCyan
            } catch {
                Write-Host "  -- Desktop $($vdIdx + 1) (switch failed, launching anyway) --" -ForegroundColor Yellow
            }
        }

        foreach ($win in $group.Group) {
            $name    = $win.ProcessName
            $exe     = $win.ExecutablePath
            $storeId = $win.StoreAppId

            if ($skip -contains $name) {
                Write-Host "  -- $name  (system, skipped)" -ForegroundColor DarkGray
                $skipped++; continue
            }

            $running = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($running) {
                Write-Host "  OK $name  (already open)" -ForegroundColor Green
                $skipped++; continue
            }

            $launched_ok = $false

            # Store / WindowsApps app
            if ($exe -like '*WindowsApps*' -or ($storeId -and $storeId -ne '')) {
                if (-not $storeId) {
                    try {
                        $entry = Get-StartApps | Where-Object { $_.Name -like "*$name*" } | Select-Object -First 1
                        if ($entry) { $storeId = $entry.AppID }
                    } catch {}
                }
                if ($storeId) {
                    try {
                        Start-Process 'explorer.exe' "shell:AppsFolder\$storeId"
                        $launched_ok = $true
                    } catch {}
                }
            }

            # Normal exe
            if (-not $launched_ok -and $exe -ne '' -and (Test-Path $exe)) {
                try { Start-Process -FilePath $exe; $launched_ok = $true } catch {}
            }

            # Fallback by name
            if (-not $launched_ok) {
                try { Start-Process $name; $launched_ok = $true } catch {}
            }

            if ($launched_ok) {
                Write-Host "  >> $name  launched" -ForegroundColor Cyan
                $launched++
                Start-Sleep -Milliseconds 400
            } else {
                Write-Host "  ?? $name  could not launch - open manually" -ForegroundColor Yellow
                $failed++
            }
        }
    }

    # Return user to Desktop 1
    if ($vdAvailable) {
        try { Switch-Desktop (Get-Desktop 0) } catch {}
    }

    Write-Host ''
    Write-Host '  -------------------------' -ForegroundColor DarkGray
    Write-Host "  Launched : $launched" -ForegroundColor Green
    Write-Host "  Skipped  : $skipped" -ForegroundColor DarkGray
    if ($failed -gt 0) {
        Write-Host "  Failed   : $failed  (open manually)" -ForegroundColor Red
    }
    Write-Host ''
}
```

- [ ] **Step 2: Verify script loads and list works**

```powershell
& 'C:\Users\anura\Documents\ws\desktop-state\desktop-state.ps1' list
```
Expected: lists existing snapshots with no errors.

- [ ] **Step 3: Integration test — snapshot then restore**

Open 2-3 apps across different virtual desktops (Win+Tab to create/switch desktops). Then:

```powershell
ds snapshot
```

Close the apps. Then:

```powershell
ds restore
```

Expected:
- Terminal prints `-- Desktop 1 --`, `-- Desktop 2 --` etc. as it groups
- Each app launches on the correct desktop
- Returns you to Desktop 1 at end
- Summary shows correct launched/skipped counts

- [ ] **Step 4: Test fallback (VD module off)**

Temporarily test what happens when module is unavailable by renaming it:
```powershell
# Simulate no module
Rename-Module VirtualDesktop VirtualDesktopDisabled -ErrorAction SilentlyContinue
ds restore
```
Expected: `VD support : OFF` in banner, apps still launch (on Desktop 1), no crashes.

Restore module after:
```powershell
Import-Module VirtualDesktop
```

- [ ] **Step 5: Commit**

```powershell
cd C:\Users\anura\Documents\ws\desktop-state
git add desktop-state.ps1
git commit -m "fix: restore apps to correct Win11 virtual desktops via launch-in-place"
```

---

### Task 4: Update Docs

**Files:**
- Modify: `docs/desktop-state.md`

- [ ] **Step 1: Update the How it works section**

Find:
```markdown
- **Restore** — reads JSON, skips system processes and already-running apps, launches the rest by exe path (falls back to process name).
```

Replace with:
```markdown
- **Restore** — reads JSON, groups apps by virtual desktop index, switches to each desktop before launching its apps (launch-in-place — no post-launch window moving). Skips system processes and already-running apps. Returns to Desktop 1 when done. Falls back to flat launch if VirtualDesktop module unavailable.
```

- [ ] **Step 2: Commit**

```powershell
cd C:\Users\anura\Documents\ws\desktop-state
git add docs/desktop-state.md
git commit -m "docs: update restore description for launch-in-place VD approach"
```
