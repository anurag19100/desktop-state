# desktop-state

A single PowerShell script (`desktop-state.ps1`, banner "Desktop State Manager v1.1") that saves and restores
a Windows desktop session. A snapshot records every visible top-level window: process name, title,
executable path, Store app id, window rectangle and, when the `VirtualDesktop` PowerShell module is
available, the virtual desktop index. Restore relaunches the apps that are not already running, on their
desktops. Windows only.

## Run

```powershell
# one-time: register the `desktop-state` function and the `ds` alias in $PROFILE
& .\setup-alias.ps1
. $PROFILE

desktop-state snapshot            # capture open windows to a JSON file
desktop-state list                # list snapshots, newest first
desktop-state restore             # relaunch from the latest snapshot
desktop-state restore -File PATH  # restore a specific snapshot
desktop-state delete              # pick (or -File PATH) and delete a snapshot
desktop-state hook -Install       # snapshot on shutdown/restart via a scheduled task (-Uninstall, -Status)
desktop-state help
```

If PowerShell blocks the script, `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`.
The script installs the `VirtualDesktop` module for the current user on first run; without it, desktop
placement is skipped.

There is no automated test suite in this repo.

## Layout

| Path | What |
|---|---|
| `desktop-state.ps1` | The tool: `snapshot`, `restore`, `list`, `delete`, `hook`, `help` |
| `setup-alias.ps1` | Adds the `desktop-state` function and `ds` alias to the PowerShell profile |
| `git-init.ps1`, `github-push.ps1` | One-off scripts that initialised the repo and created the GitHub remote |
| `demo-desktop-state.html` | Static demo page |
| `docs/desktop-state.md` | Longer usage notes |
| `docs/superpowers/` | Design spec and plan for the virtual-desktop restore |

Snapshots are written as `desktop-state_<timestamp>.json` to a snapshot directory hard-coded near the top
of `desktop-state.ps1` (`$SnapshotDir`, `C:\Users\anura\Documents\ws`). Paths inside the scripts are
absolute and specific to the author's Windows machine. `desktop-state_*.json` is git-ignored.
