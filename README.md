# ClipHistory

A minimal, native (arm64, **no Rosetta**) clipboard history manager for macOS, built for a tiny memory footprint — the resident process uses **~3.5 MB** (vs ~80 MB for some popular clipboard managers).

## How it stays small

ClipHistory is split into two processes so the heavy UI framework only lives in memory when you actually need it:

- **`ClipHistory`** — the resident daemon (**~3.5 MB**). No AppKit. It reads the
  clipboard through the low-level **Carbon Pasteboard Manager** (`ApplicationServices`),
  stores the history, and listens for the global hotkey. This is what runs 24/7.
- **`ClipHistoryPicker`** — the on-demand UI (**~16 MB, only while visible**). Launched
  by the daemon when you press the hotkey; it shows the list, pastes your choice, and
  exits immediately — so AppKit never stays resident.

Most of what a GUI app reports as memory is shared OS framework pages. By keeping the
always-on process AppKit-free, the real footprint stays tiny.

## Features

- Global hotkey **⌘⇧V** → popup list of recent clipboard entries
- Navigate with **↑/↓**, pick with **Enter** or a mouse click, **Esc** to dismiss
  (clicking outside also dismisses)
- Pastes the chosen entry into the previously focused app
- Keeps the last **50** text entries, de-duplicated (re-copying moves an entry to the top)
- History persisted to `~/Library/Application Support/ClipHistory/history.json`
- Background agent, no Dock icon (menubar 📋)

## Build

```bash
./build-daemon.sh     # compiles daemon + picker into ClipHistory.app
open ClipHistory.app
```

Requires macOS 12+.

## Permissions

- **Clipboard monitoring** and the **global hotkey** need no special permissions.
- **Auto-paste** (synthesizing ⌘V into the target app) needs **Accessibility** —
  granted to `ClipHistoryPicker` on first use. Without it, the entry is still placed
  on the clipboard; you just paste manually.

## Autostart at login

```bash
cp com.ek.cliphistoryd.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ek.cliphistoryd.plist
```

```bash
# stop / unload
launchctl bootout gui/$(id -u)/com.ek.cliphistoryd

# restart after rebuilding
launchctl kickstart -k gui/$(id -u)/com.ek.cliphistoryd
```

> Use the modern `bootstrap`/`bootout` verbs — the legacy `launchctl load`/`unload`
> report unhelpful errors (e.g. `Input/output error (5)` when already loaded).

## Project layout

| File | Purpose |
|------|---------|
| `daemon.swift` | Resident daemon: clipboard watcher + hotkey + history |
| `picker.swift` | On-demand AppKit picker UI |
| `build-daemon.sh` | Builds the two-process `ClipHistory.app` |
| `com.ek.cliphistoryd.plist` | LaunchAgent for autostart |
| `watch_test.swift` | Standalone experiment: AppKit-free clipboard watcher |

## License

MIT
