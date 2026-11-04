// Пікер: запускається на вимогу, читає історію з файлу, показує список,
// вставляє вибране й завершується. AppKit тут "живе" лише частку секунди.
import Cocoa
import Carbon

let historyURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClipHistory/history.json")

func loadHistory() -> [String] {
    guard let data = try? Data(contentsOf: historyURL),
          let items = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return items
}

enum PasteHelper {
    static func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class KeyTableView: NSTableView {
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 36, 76: onConfirm?()
        case 53:     onCancel?()
        default:     super.keyDown(with: event)
        }
    }
}

final class Picker: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var panel: KeyablePanel!
    private var table: KeyTableView!
    private let rowHeight: CGFloat = 24
    private let width: CGFloat = 520
    private var items: [String] = []
    private var prevApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Accessibility потрібен лише для авто-вставки ⌘V
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        prevApp = NSWorkspace.shared.frontmostApplication   // ДО того, як активуємось
        items = loadHistory()
        guard !items.isEmpty else { NSSound.beep(); exit(0) }

        buildPanel()
        show()
    }

    private func buildPanel() {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.delegate = self

        let visual = NSVisualEffectView()
        visual.material = .popover
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 10
        visual.layer?.masksToBounds = true

        table = KeyTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.width = width - 24
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = rowHeight
        table.backgroundColor = .clear
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(singleClick)
        table.onConfirm = { [weak self] in self?.confirm() }
        table.onCancel  = { [weak self] in exit(0) }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: visual.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: visual.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: visual.bottomAnchor, constant: -8),
        ])
        panel.contentView = visual
    }

    private func show() {
        let rows = min(items.count, 10)
        let h = CGFloat(rows) * rowHeight + 16
        panel.setContentSize(NSSize(width: width, height: h))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - width / 2, y: f.midY - h / 2))
        }
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(table)
    }

    func windowDidResignKey(_ notification: Notification) { exit(0) }

    @objc private func singleClick() {
        if table.clickedRow >= 0 {
            table.selectRowIndexes([table.clickedRow], byExtendingSelection: false)
            confirm()
        }
    }

    private func confirm() {
        let row = table.selectedRow
        guard row >= 0, row < items.count else { return }
        let chosen = items[row]
        panel.orderOut(nil)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(chosen, forType: .string)

        prevApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            PasteHelper.sendCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { exit(0) }
        }
    }

    private func display(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\t", with: " ")
         .trimmingCharacters(in: .whitespaces)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let tf: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField {
            tf = reused
        } else {
            tf = NSTextField(labelWithString: "")
            tf.identifier = id
            tf.lineBreakMode = .byTruncatingTail
            tf.font = .systemFont(ofSize: 13)
        }
        tf.stringValue = display(items[row])
        return tf
    }
}

let app = NSApplication.shared
let picker = Picker()
app.delegate = picker
app.run()
