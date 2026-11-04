// Резидентний демон: стежить за буфером + ловить ⌘⇧V + запускає пікер.
// БЕЗ AppKit. Доступ до буфера — Carbon Pasteboard Manager.
import ApplicationServices
import Carbon
import Foundation

// MARK: - Шлях до історії (спільний з пікером)

let historyURL: URL = {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ClipHistory", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("history.json")
}()

let pickerPath = CommandLine.arguments.first.map {
    (($0 as NSString).deletingLastPathComponent as NSString).appendingPathComponent("ClipHistoryPicker")
} ?? "./ClipHistoryPicker"

// MARK: - Історія (у памʼяті + файл)

var history: [String] = []
let maxItems = 50

func addToHistory(_ s: String) {
    if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
    if let idx = history.firstIndex(of: s) { history.remove(at: idx) }
    history.insert(s, at: 0)
    if history.count > maxItems { history.removeLast(history.count - maxItems) }
    if let data = try? JSONEncoder().encode(history) {
        try? data.write(to: historyURL)
    }
}

// MARK: - Watcher (Carbon Pasteboard)

var pb: Pasteboard?
guard PasteboardCreate(kPasteboardClipboard as CFString, &pb) == noErr, let pb = pb else {
    FileHandle.standardError.write("pb create failed\n".data(using: .utf8)!); exit(1)
}

func currentText() -> String? {
    var count = 0
    guard PasteboardGetItemCount(pb, &count) == noErr, count >= 1 else { return nil }
    for i in 1...count {
        var itemID: PasteboardItemID? = nil
        guard PasteboardGetItemIdentifier(pb, i, &itemID) == noErr, let id = itemID else { continue }
        var data: CFData? = nil
        if PasteboardCopyItemFlavorData(pb, id, "public.utf8-plain-text" as CFString, &data) == noErr,
           let cf = data { return String(data: cf as Data, encoding: .utf8) }
    }
    return nil
}

let pollTimer = Timer(timeInterval: 0.5, repeats: true) { _ in
    let flags = PasteboardSynchronize(pb)
    if (flags.rawValue & PasteboardSyncFlags.modified.rawValue) != 0 {
        if let s = currentText() { addToHistory(s) }
    }
}
RunLoop.current.add(pollTimer, forMode: .common)

// MARK: - Запуск пікера

func launchPicker() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: pickerPath)
    try? p.run()
}

// MARK: - Глобальний хоткей ⌘⇧V

final class HotKey {
    var ref: EventHotKeyRef?
    static let shared = HotKey()
    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            launchPicker(); return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x43484953), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }
}
HotKey.shared.install()

FileHandle.standardError.write("daemon up, pid=\(getpid())\n".data(using: .utf8)!)
CFRunLoopRun()
