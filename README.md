# ClipHistory

> **Active version is now the C++ rewrite in [`cpp/`](cpp/README.md).**
> The resident daemon was rebuilt in C++ **without AppKit** (hotkey via
> `CGEventTap` instead of a Carbon hotkey), cutting idle private memory from
> **~7.6 MB → ~2.4 MB** (`phys_footprint`). The C++ daemon is what autostarts
> (LaunchAgent `com.ek.cliphistorycpp`), keeps its own history at
> `~/Library/Application Support/ClipHistoryCpp/history.json`, and now needs the
> **Accessibility** permission (the Swift/Carbon hotkey did not). The Swift
> sources below remain the original design/reference and are no longer in
> autostart. See [`cpp/README.md`](cpp/README.md) for the comparison and setup.

A minimal, native (arm64, **no Rosetta**) clipboard history manager for macOS, built for a tiny memory footprint — the resident process uses **~7.5 MB** of private memory (`phys_footprint`) vs ~80 MB for some popular clipboard managers.

> **Note on numbers:** Activity Monitor / `ps` will show the daemon at ~60 MB RSS, but
> that is almost entirely *shared* AppKit framework pages counted against every GUI
> process. The honest metric is `phys_footprint` (private dirty memory): **~7.5 MB**.
> Check it with `footprint $(pgrep -f MacOS/ClipHistory)`.

## How it stays small

ClipHistory is split into two processes so the heavy *UI* only lives in memory when you
actually need it:

- **`ClipHistory`** — the resident daemon. Links AppKit but runs **headless**
  (`NSApplication` with `.accessory` activation policy — no Dock icon, no menu bar,
  no windows). It watches the clipboard (`NSPasteboard.changeCount`), stores the
  history, and listens for the global hotkey. This is what runs 24/7.
- **`ClipHistoryPicker`** — the on-demand UI (**~16 MB, only while visible**). Launched
  by the daemon when you press the hotkey; it shows the list, pastes your choice, and
  exits immediately — so the picker's UI objects never stay resident.

> **Why the daemon links AppKit** (it didn't originally): a global Carbon hotkey
> (`RegisterEventHotKey`) is only *delivered* to a process that has a connection to the
> WindowServer. A pure Foundation/Carbon binary can poll the clipboard fine, but the
> hotkey registration silently succeeds (`status == 0`) while **no key events ever
> arrive**. Initializing `NSApplication` establishes that connection. See
> Troubleshooting → "hotkey does nothing".

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
./make-signing-cert.sh   # ONE TIME — stable code-signing cert (see below)
./build-daemon.sh        # compiles daemon + picker into ClipHistory.app
open ClipHistory.app
```

Requires macOS 12+.

### Code signing (do this first)

`build-daemon.sh` signs with a stable self-signed certificate **if one exists**,
otherwise it falls back to **ad-hoc** signing. Ad-hoc signatures have no stable
identity, so macOS **re-asks for Accessibility every launch** (see Troubleshooting).
Run `./make-signing-cert.sh` once (needs your admin password) to create the
`ClipHistory Self-Signed` cert; every build after that is stably signed and permissions
stick. The cert survives rebuilds — you only make it once.

## Permissions

- **Clipboard monitoring** and the **global hotkey** need no special permissions.
- **Auto-paste** (synthesizing ⌘V into the target app) needs **Accessibility**. The
  picker is spawned by the daemon, so TCC attributes the grant to the **daemon**
  (`com.ek.cliphistory`) — that single toggle covers the picker too. On macOS Tahoe the
  pane is **System Settings → Privacy & Security → Accessibility** (also surfaced under
  "Device Control and Data Access"). Without it, the entry is still placed on the
  clipboard; you just paste manually.

## Autostart at login

**Use exactly one autostart source.** This LaunchAgent is it — do **not** also add the
app under System Settings → Login Items, or you get two daemons fighting over the hotkey
after every reboot (see Troubleshooting).

```bash
cp com.ek.cliphistoryd.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ek.cliphistoryd.plist
```

The agent launches the app via `/usr/bin/open -W ClipHistory.app` (LaunchServices),
**not** by exec'ing the binary directly. LaunchServices gives the process the proper
WindowServer/TCC context; `-W` keeps `open` alive for as long as the app runs, so
`KeepAlive` still restarts it on a crash.

```bash
# stop / unload
launchctl bootout gui/$(id -u)/com.ek.cliphistoryd

# restart after rebuilding
launchctl kickstart -k gui/$(id -u)/com.ek.cliphistoryd
```

> Use the modern `bootstrap`/`bootout` verbs — the legacy `launchctl load`/`unload`
> report unhelpful errors (e.g. `Input/output error (5)` when already loaded).

## Troubleshooting

**Two `ClipHistory` processes after reboot / hotkey stops working.**
You have two autostart sources. Check both and keep only the LaunchAgent:
```bash
launchctl list | grep cliphistory
osascript -e 'tell application "System Events" to get name of every login item'
```
Remove a stray Login Item with:
```bash
osascript -e 'tell application "System Events" to delete login item "ClipHistory"'
```

**Hotkey ⌘⇧V does nothing (but clipboard history still updates).**
The daemon isn't connected to the WindowServer, so Carbon never delivers the hotkey
even though `RegisterEventHotKey` returned `0`. The daemon must init `NSApplication`
(`.accessory`) — this is already the case in `daemon.swift`; if you strip AppKit out to
save memory, the hotkey breaks. Launching the binary directly instead of via `open`
(LaunchServices) can also break delivery.

**macOS asks for Accessibility every single launch.**
Ad-hoc signing → unstable identity → TCC can't remember the grant. Fix:
```bash
./make-signing-cert.sh          # once
./build-daemon.sh               # re-sign with the cert
tccutil reset Accessibility com.ek.cliphistory
# then trigger the hotkey once and grant permission — it now sticks
```
After *any* change to the cert/identity, reset TCC and re-grant once.

**Picking an item pastes the *last copied* item instead of the selected one.**
A regression where `windowDidResignKey` called `exit(0)`: hiding the panel resigned key
and killed the process *before* the chosen text was written to the clipboard. The picker
now sets the clipboard **before** hiding the panel and guards the resign handler with a
`confirming` flag. If you touch `confirm()` / `windowDidResignKey`, preserve that order.

## Project layout

| File | Purpose |
|------|---------|
| `daemon.swift` | Resident daemon: clipboard watcher + hotkey + history |
| `picker.swift` | On-demand AppKit picker UI |
| `build-daemon.sh` | Builds + signs the two-process `ClipHistory.app` |
| `make-signing-cert.sh` | One-time: creates the stable self-signed code-signing cert |
| `com.ek.cliphistoryd.plist` | LaunchAgent for autostart (via `open -W`) |
| `watch_test.swift` | Standalone experiment: AppKit-free clipboard watcher |

## License

MIT
