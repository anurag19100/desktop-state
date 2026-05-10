# Design: desktop-state Virtual Desktop Restore Fix

**Date:** 2026-05-11
**Scope:** Fix virtual desktop restore on Windows 11 — all apps currently land on Desktop 1 instead of their captured desktop.

---

## Problem

`Invoke-Restore` uses `Move-Window` from the `VirtualDesktop` PowerShell module to move launched apps to their correct virtual desktop. On Windows 11, Microsoft changed internal COM interface GUIDs between builds, making `Move-Window` silently fail. Result: every app opens on Desktop 1 regardless of what was captured.

---

## Approach: Launch-in-Place (Option B)

Switch the active virtual desktop **before** launching each app. Apps always open on whichever desktop is currently active — no post-launch move needed. Removes the `Move-Window` / `Wait-ForWindow` dependency entirely.

Trade-off: user sees desktops flickering during restore. Acceptable — restore is a deliberate action, not background work.

---

## Architecture

No new files. All changes in `desktop-state.ps1` (`Invoke-Restore` function).

### Restore Sequence

```
1. Read snapshot JSON
2. Create any missing virtual desktops up-front
3. Group windows by VirtualDesktop index (ascending)
4. For each desktop group:
     a. Switch-Desktop $idx          ← makes this desktop active
     b. Sleep 300ms                  ← wait for desktop animation
     c. For each app in group:
          - Skip if system process
          - Skip if already running
          - Launch via exe / store ID / name fallback
          - Sleep 400ms              ← window registration time
5. Switch-Desktop 0                  ← return user to Desktop 1
6. Print summary: launched / skipped / failed
```

### Module Version Guard

On script load, after `Import-Module VirtualDesktop`:
- Check `(Get-Module VirtualDesktop).Version.Major`
- If `< 2`: run `Install-Module VirtualDesktop -Scope CurrentUser -Force -AllowClobber`
- Win11 requires VirtualDesktop `≥ 2.x` for `Switch-Desktop` to work

### Fallback

If `$vdAvailable` is false (module missing/broken): fall back to current flat-launch behavior (no desktop switching, apps open wherever Windows places them).

---

## Changes

| Area | Change |
|---|---|
| `Invoke-Restore` | Group by VD index, `Switch-Desktop` before each group, `Switch-Desktop 0` at end |
| `Invoke-Restore` | Remove `Wait-ForWindow` call and `Move-ToDesktop` call |
| Module init block | Add version check — force-update if `< 2.x` |
| `Move-ToDesktop` | Delete (no longer used) |
| `Wait-ForWindow` | Delete (no longer used) |

---

## Out of Scope

- Auto-snapshot scheduling (user confirmed manual `ds snapshot` is sufficient)
- Window position/size restore (not requested)
- Named sessions / workspaces
