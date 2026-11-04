// Резидентний демон: стежить за буфером + ловить ⌘⇧V + запускає пікер.
// AppKit потрібен, щоб процес мав зʼєднання з WindowServer — інакше
// глобальний Carbon-хоткей реєструється, але події до нас не доставляються.
// Працюємо як .accessory (без іконки в Dock, без меню-бару).
import Cocoa
import Carbon

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

// MARK: - Watcher (NSPasteboard changeCount)

let generalPB = NSPasteboard.general
var lastChangeCount = generalPB.changeCount

func pollPasteboard() {
    let cc = generalPB.changeCount
    if cc != lastChangeCount {
        lastChangeCount = cc
        if let s = generalPB.string(forType: .string) { addToHistory(s) }
    }
}

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
        let st = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey),
                                     id, GetApplicationEventTarget(), 0, &ref)
        FileHandle.standardError.write("RegisterEventHotKey status=\(st)\n".data(using: .utf8)!)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var timer: Timer?
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HotKey.shared.install()
        let t = Timer(timeInterval: 0.5, repeats: true) { _ in pollPasteboard() }
        RunLoop.current.add(t, forMode: .common)
        timer = t
        FileHandle.standardError.write("daemon up, pid=\(getpid())\n".data(using: .utf8)!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
