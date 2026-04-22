param(
    [Parameter(Position=0)][string]$Command = 'help',
    [string]$File = ''
)

$SnapshotDir = 'C:\Users\anura\Documents\ws'

# Win32 API - closing "@ must stay at column 0, no indentation
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinHelper {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@ -ErrorAction SilentlyContinue

# ── Virtual Desktop module ────────────────────────────────────────────────────
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

# ── Banner ────────────────────────────────────────────────────────────────────
function Show-Banner {
    Write-Host ''
    Write-Host '  =================================' -ForegroundColor Cyan
    Write-Host '    Desktop State Manager  v1.1   ' -ForegroundColor Cyan
    Write-Host '  =================================' -ForegroundColor Cyan
    Write-Host ''
}

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-Snapshots {
    Get-ChildItem -Path $SnapshotDir -Filter 'desktop-state_*.json' |
        Sort-Object LastWriteTime -Descending
}

function Pick-Snapshot {
    param([string]$Prompt = 'Select a snapshot')
    $snaps = Get-Snapshots
    if ($snaps.Count -eq 0) {
        Write-Host '  No snapshots found.' -ForegroundColor Red
        return $null
    }
    Write-Host "  $Prompt" -ForegroundColor Yellow
    Write-Host ''
    for ($i = 0; $i -lt $snaps.Count; $i++) {
        try {
            $d  = Get-Content $snaps[$i].FullName -Encoding UTF8 | ConvertFrom-Json
            $wc = if ($d.WindowCount) { $d.WindowCount } else { '?' }
        } catch { $wc = '?' }
        $num  = $i + 1
        $name = $snaps[$i].Name
        Write-Host "  [$num]  $name   ($wc windows)" -ForegroundColor White
    }
    Write-Host ''
    $choice = Read-Host '  Enter number (0 to cancel)'
    if ($choice -eq '0' -or $choice -eq '') { return $null }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $snaps.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        return $null
    }
    return $snaps[$idx].FullName
}

# Get virtual desktop index (0-based) for a process handle
function Get-VDIndex {
    param($handle)
    if (-not $vdAvailable) { return -1 }
    try {
        $desktop = Get-DesktopFromWindow $handle
        return Get-DesktopIndex $desktop
    } catch { return -1 }
}

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

# ── SNAPSHOT ──────────────────────────────────────────────────────────────────
function Invoke-Snapshot {
    Write-Host '  Capturing desktop state...' -ForegroundColor Cyan
    if ($vdAvailable) {
        $total = Get-DesktopCount
        Write-Host "  Virtual desktops detected: $total" -ForegroundColor DarkGray
    } else {
        Write-Host '  (VirtualDesktop module not available - desktop index not recorded)' -ForegroundColor DarkGray
    }
    Write-Host ''

    try { powercfg /hibernate on 2>$null } catch {}

    $windows = Get-Process | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero -and
        $_.MainWindowTitle  -ne '' -and
        [WinHelper]::IsWindowVisible($_.MainWindowHandle)
    } | ForEach-Object {
        $proc = $_
        $rect = New-Object WinHelper+RECT
        [WinHelper]::GetWindowRect($proc.MainWindowHandle, [ref]$rect) | Out-Null
        $exe = ''; try { $exe = $proc.Path } catch {}

        # Virtual desktop index
        $vdIndex = Get-VDIndex $proc.MainWindowHandle

        # Store App ID for WindowsApps
        $appId = ''
        if ($exe -like '*WindowsApps*') {
            try {
                $entry = Get-StartApps | Where-Object { $_.Name -like "*$($proc.ProcessName)*" } | Select-Object -First 1
                if ($entry) { $appId = $entry.AppID }
            } catch {}
        }

        [PSCustomObject]@{
            ProcessName    = $proc.ProcessName
            WindowTitle    = $proc.MainWindowTitle
            ExecutablePath = $exe
            StoreAppId     = $appId
            VirtualDesktop = $vdIndex
            PID            = $proc.Id
            Window         = [PSCustomObject]@{
                Left   = $rect.Left;  Top    = $rect.Top
                Right  = $rect.Right; Bottom = $rect.Bottom
                Width  = $rect.Right - $rect.Left
                Height = $rect.Bottom - $rect.Top
            }
            CapturedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    }

    $ts  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $out = Join-Path $SnapshotDir "desktop-state_$ts.json"
    $cnt = $windows.Count

    [PSCustomObject]@{
        SavedAt        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        ComputerName   = $env:COMPUTERNAME
        UserName       = $env:USERNAME
        WindowCount    = $cnt
        DesktopCount   = if ($vdAvailable) { Get-DesktopCount } else { 1 }
        Windows        = $windows
    } | ConvertTo-Json -Depth 6 | Out-File -FilePath $out -Encoding UTF8

    Write-Host '  Captured apps:' -ForegroundColor White
    $windows | ForEach-Object {
        $title = $_.WindowTitle
        if ($title.Length -gt 45) { $title = $title.Substring(0,45) + '...' }
        $pn  = $_.ProcessName
        $vd  = if ($_.VirtualDesktop -ge 0) { '  [Desktop ' + ($_.VirtualDesktop + 1) + ']' } else { '' }
        Write-Host "    - $pn$vd  |  $title" -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host "  Snapshot saved: $cnt windows" -ForegroundColor Green
    Write-Host "  File: $out" -ForegroundColor DarkGray
    Write-Host ''
}

# ── RESTORE ───────────────────────────────────────────────────────────────────
function Invoke-Restore {
    param([string]$JsonFile)

    if ($JsonFile -eq '') {
        $snaps = Get-Snapshots
        if ($snaps.Count -eq 0) {
            Write-Host '  No snapshots found. Run: desktop-state snapshot' -ForegroundColor Red
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
    Write-Host "  Computer   : $($data.ComputerName)" -ForegroundColor White
    Write-Host "  Windows    : $($data.WindowCount)" -ForegroundColor White
    if ($vdAvailable) {
        Write-Host '  VD support : ON - apps will be placed on correct desktops' -ForegroundColor Green
    } else {
        Write-Host '  VD support : OFF - run: Install-Module VirtualDesktop' -ForegroundColor Yellow
    }
    Write-Host ''

    $skip = @('explorer','SearchHost','StartMenuExperienceHost','ShellExperienceHost',
               'TextInputHost','SystemSettings','ApplicationFrameHost','ctfmon',
               'dwm','csrss','winlogon','taskhostw','sihost','fontdrvhost','lsass','svchost')

    $launched = 0; $skipped = 0; $failed = 0

    foreach ($win in $data.Windows) {
        $name    = $win.ProcessName
        $exe     = $win.ExecutablePath
        $storeId = $win.StoreAppId
        $vdIdx   = if ($null -ne $win.VirtualDesktop) { [int]$win.VirtualDesktop } else { -1 }
        $vdLabel = if ($vdIdx -ge 0) { ' -> Desktop ' + ($vdIdx + 1) } else { '' }

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
            Write-Host "  >> $name  launched$vdLabel" -ForegroundColor Cyan
            $launched++

            # Move to correct virtual desktop
            if ($vdAvailable -and $vdIdx -ge 0) {
                $proc = Wait-ForWindow -ProcessName $name -TimeoutSec 10
                if ($proc) {
                    Move-ToDesktop -process $proc -desktopIndex $vdIdx
                }
            } else {
                Start-Sleep -Milliseconds 400
            }
        } else {
            Write-Host "  ?? $name  could not launch - open manually" -ForegroundColor Yellow
            $failed++
        }
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

# ── LIST ──────────────────────────────────────────────────────────────────────
function Invoke-List {
    $snaps = Get-Snapshots
    if ($snaps.Count -eq 0) {
        Write-Host "  No snapshots found in: $SnapshotDir" -ForegroundColor Yellow
        Write-Host ''
        return
    }
    Write-Host '  #   Name                                    Windows  Saved At' -ForegroundColor Cyan
    Write-Host '  -----------------------------------------------------------------' -ForegroundColor DarkGray
    $i = 1
    foreach ($snap in $snaps) {
        try {
            $d  = Get-Content $snap.FullName -Encoding UTF8 | ConvertFrom-Json
            $wc = if ($d.WindowCount) { $d.WindowCount } else { '?' }
            $at = if ($d.SavedAt)     { $d.SavedAt }     else { '?' }
        } catch { $wc = '?'; $at = '?' }
        $tag  = if ($i -eq 1) { '  <- latest' } else { '' }
        $num  = $i
        $nm   = $snap.Name
        Write-Host "  $num   $nm   $wc   $at$tag" -ForegroundColor White
        $i++
    }
    $total = $snaps.Count
    Write-Host ''
    Write-Host "  Total: $total snapshot(s)" -ForegroundColor DarkGray
    Write-Host ''
}

# ── DELETE ────────────────────────────────────────────────────────────────────
function Invoke-Delete {
    param([string]$JsonFile)

    if ($JsonFile -eq '') {
        $JsonFile = Pick-Snapshot -Prompt 'Which snapshot do you want to delete?'
        if ($null -eq $JsonFile) {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            return
        }
    }

    if (-not (Test-Path $JsonFile)) {
        Write-Host "  File not found: $JsonFile" -ForegroundColor Red
        return
    }

    $nm = Split-Path $JsonFile -Leaf
    Write-Host ''
    Write-Host "  About to delete: $nm" -ForegroundColor Yellow
    $confirm = Read-Host '  Are you sure? (yes / no)'

    if ($confirm -match '^y') {
        Remove-Item $JsonFile -Force
        Write-Host "  Deleted: $nm" -ForegroundColor Green
    } else {
        Write-Host '  Cancelled - file kept.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ── HELP ──────────────────────────────────────────────────────────────────────
function Invoke-Help {
    Write-Host '  COMMANDS' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  desktop-state snapshot              Save current desktop to JSON' -ForegroundColor White
    Write-Host '  desktop-state restore               Restore from latest snapshot' -ForegroundColor White
    Write-Host '  desktop-state restore -File PATH    Restore from specific snapshot' -ForegroundColor White
    Write-Host '  desktop-state list                  List all saved snapshots' -ForegroundColor White
    Write-Host '  desktop-state delete                Pick and delete a snapshot' -ForegroundColor White
    Write-Host '  desktop-state delete -File PATH     Delete a specific snapshot' -ForegroundColor White
    Write-Host '  desktop-state help                  Show this help' -ForegroundColor White
    Write-Host ''
    Write-Host '  SHORT ALIAS: ds snapshot / ds restore / ds list / ds delete' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  TIPS' -ForegroundColor Cyan
    Write-Host '  - Snapshots saved to: C:\Users\anura\Documents\ws' -ForegroundColor DarkGray
    Write-Host '  - VD support needs: Install-Module VirtualDesktop -Scope CurrentUser' -ForegroundColor DarkGray
    Write-Host '  - Use Hibernate (Start > Power > Hibernate) to freeze state perfectly' -ForegroundColor DarkGray
    Write-Host ''
}

# ── ROUTER ────────────────────────────────────────────────────────────────────
Show-Banner

switch ($Command) {
    'snapshot' { Invoke-Snapshot }
    'restore'  { Invoke-Restore -JsonFile $File }
    'list'     { Invoke-List }
    'delete'   { Invoke-Delete -JsonFile $File }
    default    { Invoke-Help }
}
