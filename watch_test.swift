// Тест: чистий watcher буфера БЕЗ AppKit (Carbon Pasteboard Manager)
import ApplicationServices
import Foundation

var pb: Pasteboard?
guard PasteboardCreate(kPasteboardClipboard as CFString, &pb) == noErr,
      let pb = pb else {
    FileHandle.standardError.write("pb create failed\n".data(using: .utf8)!)
    exit(1)
}

func currentText() -> String? {
    var count: Int = 0
    guard PasteboardGetItemCount(pb, &count) == noErr, count >= 1 else { return nil }
    for i in 1...count {
        var itemID: PasteboardItemID? = nil
        guard PasteboardGetItemIdentifier(pb, i, &itemID) == noErr,
              let id = itemID else { continue }
        var data: CFData? = nil
        if PasteboardCopyItemFlavorData(pb, id, "public.utf8-plain-text" as CFString, &data) == noErr,
           let cf = data {
            return String(data: cf as Data, encoding: .utf8)
        }
    }
    return nil
}

FileHandle.standardError.write("watcher up, pid=\(getpid())\n".data(using: .utf8)!)
while true {
    let flags = PasteboardSynchronize(pb)
    if (flags.rawValue & PasteboardSyncFlags.modified.rawValue) != 0 {
        if let s = currentText() {
            let line = "changed: \(s.prefix(40))\n"
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }
    }
    usleep(500_000)
}
