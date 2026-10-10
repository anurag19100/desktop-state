# AGENTS.md

Rules for AI agents working in this repo. Human-facing overview: `README.md`.

- **Where code lives:** everything is in `desktop-state.ps1`. `setup-alias.ps1` edits the user's PowerShell
  profile; `git-init.ps1` and `github-push.ps1` touch git and GitHub. Design notes are in `docs/`.
- **Platform:** Windows PowerShell with Win32 and `VirtualDesktop` module calls. It cannot run on
  Linux or macOS, so do not claim a change was run unless it was run on Windows.
- **Testing:** there is no test suite. Check syntax by reading, and say what you did not execute.
  Never run `snapshot`, `restore`, `delete` or `hook` against a real session as a test: restore launches
  programs, delete removes files, and hook registers a scheduled task.
- **Do not touch:** snapshot JSON files (they are git-ignored and personal); the scheduled task
  `DesktopStateShutdownHook`; the user's `$PROFILE`. The `Add-Type @"` here-string in `desktop-state.ps1`
  must keep its closing `"@` at column 0.
- **Secrets:** never read `.env*` files or credentials. Do not commit snapshots, which contain window titles.
- **Workflow:** work in a git worktree, not the main checkout; commit with path-scoped adds; open a PR
  against `master`. Commit hooks (gitleaks) must pass and are never bypassed.
