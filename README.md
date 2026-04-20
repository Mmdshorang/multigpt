<div align="center">

# MultiCodex

**Manage multiple Codex accounts from your Mac menu bar.**

Track usage across accounts. Switch instantly. Never hit a rate limit unprepared.

[Download Latest](https://github.com/momoazn/multicodex/releases/latest) · [Report a Bug](https://github.com/momoazn/multicodex/issues) · [Development Guide](docs/DEVELOPMENT.md)

</div>

---

## Why MultiCodex?

If you use Codex with multiple accounts, you know the friction — checking which account has headroom, manually switching when one runs out, losing track of where you are.

MultiCodex makes it invisible. It lives in your menu bar and handles the bookkeeping so you can focus on coding.

## Features

### 📊 Usage at a Glance

See 5-hour and weekly usage for your active account as soon as you click the menu bar icon. Progress rings, compact bars, and percentage readouts — all updating in the background.

### ⚡ Instant Account Switching

One click to switch between accounts. No terminal commands, no editing config files. Switch, re-login, or check auth status — all from the menu.

### 🔄 Smart Auto-Switching

Let MultiCodex switch accounts for you:

| Strategy | When it switches |
|----------|-----------------|
| **Manual** | Never — you're in control |
| **Failover** | When the current account is near its limit or needs re-auth |
| **Expiry-Aware** | To the account with the most usage that's about to reset, so nothing goes to waste |

Get a native macOS notification every time it happens.

### 🗂️ Flexible Sorting

Sort your account list by usage, remaining headroom, or name. Choose the time window (5h or weekly) and direction. Your sort preference syncs between the menu bar and settings — set it once, see it everywhere.

### ⚙️ Full Settings Panel

A native settings window with everything you need:

- **General** — appearance, density, bar style, auto-switching config
- **Accounts** — login, rename, remove, check status, view per-account usage
- **System** — Codex CLI path, diagnostics, cache interval
- **About** — version info, keyboard shortcuts, support links

### 🧑‍💻 Developer-Friendly

- Pure Swift — no Electron, no Node, no JS runtime bundled
- Built with SwiftUI and modern concurrency
- Clean architecture with layered separation of concerns
- ~8,200 lines of source, ~2,400 lines of tests

## Installation

### Download

Grab the latest DMG from [Releases](https://github.com/momoazn/multicodex/releases/latest).

### Install

1. Open the DMG
2. Drag **MultiCodex.app** to **Applications**
3. Run this command (unsigned app — macOS requires it once):

```bash
sudo xattr -dr com.apple.quarantine /Applications/MultiCodex.app
```

4. Launch MultiCodex from Applications

### Requirements

- macOS 13 (Ventura) or later
- [Codex CLI](https://github.com/openai/codex) installed and in your `PATH` (or set a custom path in Settings → System)

## Getting Started

1. **Launch MultiCodex** — the menu bar icon appears
2. **Login your first account** — click the icon, then "Login First Account"
3. **Add more accounts** — use "Login New" to add additional accounts
4. **Configure auto-switching** — open Settings → General and pick a strategy

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ R` | Refresh usage |
| `⌘ ,` | Open settings |

## Building from Source

You'll need Xcode 15+ and [just](https://github.com/casey/just):

```bash
git clone https://github.com/momoazn/multicodex.git
cd multicodex
just doctor    # verify your toolchain
just run       # build and launch
```

For the full development reference, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes and add tests
4. Run `just check` to verify everything passes
5. Open a pull request

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for architecture details, common tasks, and coding patterns.

## License

This project is licensed under the terms found in the [LICENSE](LICENSE) file.

---

<div align="center">

Built with ❤️ using Swift and SwiftUI

</div>
