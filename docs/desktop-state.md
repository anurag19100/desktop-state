# desktop-state

Save, restore, list, and delete Windows desktop session snapshots.

---

## Setup (one-time)

**1. Register the alias** — paste in PowerShell:
```powershell
Add-Content $PROFILE "`nfunction desktop-state { param([Parameter(Position=0)][string]`$Command='help',[string]`$File='') & 'C:\Users\anura\Documents\ws\desktop-state.ps1' -Command `$Command -File `$File }`nfunction ds { desktop-state @args }"
```

**2. Activate it:**
```powershell
. $PROFILE
```

> If you hit an execution policy error first run:
> `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

---

## Commands

| Command | What it does |
|---|---|
| `desktop-state snapshot` | Capture all open windows to JSON |
| `desktop-state restore` | Relaunch apps from latest snapshot |
| `desktop-state restore -File PATH` | Restore from a specific snapshot |
| `desktop-state list` | Show all saved snapshots |
| `desktop-state delete` | Pick and delete a snapshot |
| `desktop-state help` | Show help |

Short alias: `ds snapshot`, `ds restore`, `ds list`, `ds delete`

---

## Files

```
C:\Users\anura\Documents\ws\
├── desktop-state.ps1        # main script (all logic)
├── setup-alias.ps1          # alias installer
├── demo-desktop-state.html  # interactive browser demo
└── desktop-state_*.json     # snapshots (auto-generated)
```

---

## How it works

- **Snapshot** — queries all visible processes with a window handle, captures name, title, exe path, and pixel position via Win32 `GetWindowRect`. Saves to timestamped JSON. Silently enables Hibernate.
- **Restore** — reads JSON, skips system processes and already-running apps, launches the rest by exe path (falls back to process name).
- **List / Delete** — file operations on the snapshot folder with an interactive picker.

---

## Hibernate (recommended)

Hibernate freezes your exact RAM state — all windows, positions, and content survive a power-off. Enable once:
```powershell
powercfg /hibernate on
```
Then use **Start → Power → Hibernate** instead of Shut Down.

> `desktop-state snapshot` enables Hibernate automatically on first run.

---

## Snapshot format

```json
{
  "SavedAt": "2026-04-19 14:32:07",
  "ComputerName": "ROCKY-PC",
  "WindowCount": 7,
  "Windows": [
    {
      "ProcessName": "Code",
      "WindowTitle": "ruflo-v3 — Visual Studio Code",
      "ExecutablePath": "C:\\...\\Code.exe",
      "Window": { "Left": 0, "Top": 0, "Width": 1920, "Height": 1080 }
    }
  ]
}
```
