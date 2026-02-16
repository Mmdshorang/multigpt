## MultiCodex

Native menu bar app release.

### Highlights

- Manage multiple Codex profiles directly from the menu bar.
- Switch profiles quickly and re-login when auth is required.
- View 5h and weekly usage at a glance.
- Fully native Swift runtime (no bundled JavaScript CLI runtime).

### Install

Important (unsigned app): run this after dragging to Applications.

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
