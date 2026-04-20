## MultiCodex

Native menu bar app for managing multiple Codex CLI accounts.

### Highlights

- **Usage Dashboard** — 5h and weekly usage as progress rings and compact bars
- **Account Switching** — Switch between accounts instantly from the menu bar
- **Auto-Switching** — Optional automatic switching (Failover or Expiry-Aware strategies)
- **Account Sorting** — Sort by Used, Remaining, or Name with configurable window and direction
- **Notifications** — macOS native alerts when accounts auto-switch
- **Settings Panel** — Full settings window with General, Accounts, System, and About sections
- **Fully Native** — Pure Swift implementation, no bundled JavaScript runtime

### Install

1. Download `MultiCodex.dmg` from this release.
2. Open the DMG and drag `MultiCodex.app` into Applications.
3. Run once in Terminal (unsigned app):
   ```bash
   sudo xattr -dr com.apple.quarantine /Applications/MultiCodex.app
   ```
4. Launch the app from Applications.

### Requirements

- macOS 13+
- `codex` CLI must be available on the target machine (`PATH`) or configured in app Settings.
