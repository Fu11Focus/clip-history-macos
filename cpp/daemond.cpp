// Резидентний демон (C++ варіант, БЕЗ AppKit).
//
// Відмінність від Swift-версії: Swift-демон лінкує AppKit лише заради того,
// щоб мати конекшен до WindowServer — інакше глобальний Carbon-хоткей
// (RegisterEventHotKey) реєструється, але події не доставляються.
//
// Тут ми обходимось без AppKit: хоткей ловимо через CGEventTap на «голому»
// CFRunLoop. Плата за це — демону потрібен дозвіл Accessibility (Carbon-хоткею
// у Swift-версії він не був потрібен — лише пікеру для авто-вставки).
//
// Стеження за буфером — через Pasteboard Manager (чистий C API з
// ApplicationServices), без NSPasteboard.
//
// Лінкує: ApplicationServices (Pasteboard + CoreGraphics event tap),
//         CoreFoundation. НЕ лінкує AppKit і НЕ тягне Swift runtime.

#include <ApplicationServices/ApplicationServices.h>
#include <spawn.h>
#include <unistd.h>
#include <libgen.h>
#include <sys/stat.h>
#include <cctype>
#include <string>
#include <vector>
#include <cstdio>
#include <cstring>

extern char **environ;

// MARK: - Шлях до історії (окремий від Swift-версії, щоб не конфліктувати)

static std::string historyPath() {
    const char *home = getenv("HOME");
    std::string dir = std::string(home ? home : ".") +
        "/Library/Application Support/ClipHistoryCpp";
    // mkdir -p (одна вкладеність достатня — Application Support вже існує)
    mkdir((std::string(home ? home : ".") + "/Library/Application Support").c_str(), 0755);
    mkdir(dir.c_str(), 0755);
    return dir + "/history.json";
}

static std::string gHistoryPath;
static std::string gPickerPath;

// MARK: - Історія (у памʼяті + файл)

static std::vector<std::string> gHistory;
static const size_t kMaxItems = 50;

static std::string jsonEscape(const std::string &s) {
    std::string out;
    out.reserve(s.size() + 2);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += (char)c; // UTF-8 байти >= 0x80 валідні в JSON як є
                }
        }
    }
    return out;
}

static void saveHistory() {
    std::string json = "[";
    for (size_t i = 0; i < gHistory.size(); ++i) {
        if (i) json += ",";
        json += "\"" + jsonEscape(gHistory[i]) + "\"";
    }
    json += "]";
    FILE *f = fopen(gHistoryPath.c_str(), "wb");
    if (f) {
        fwrite(json.data(), 1, json.size(), f);
        fclose(f);
    }
}

static bool isBlank(const std::string &s) {
    for (unsigned char c : s)
        if (!isspace(c)) return false;
    return true;
}

static void addToHistory(const std::string &s) {
    if (isBlank(s)) return;
    for (size_t i = 0; i < gHistory.size(); ++i) {
        if (gHistory[i] == s) { gHistory.erase(gHistory.begin() + i); break; }
    }
    gHistory.insert(gHistory.begin(), s);
    if (gHistory.size() > kMaxItems)
        gHistory.resize(kMaxItems);
    saveHistory();
}

// MARK: - Watcher (Pasteboard Manager changeCount)

static PasteboardRef gPasteboard = NULL;

static void readPasteboardString() {
    ItemCount n = 0;
    if (PasteboardGetItemCount(gPasteboard, &n) != noErr || n < 1) return;

    PasteboardItemID itemID = NULL;
    if (PasteboardGetItemIdentifier(gPasteboard, 1, &itemID) != noErr) return;

    CFDataRef data = NULL;
    OSStatus st = PasteboardCopyItemFlavorData(
        gPasteboard, itemID, CFSTR("public.utf8-plain-text"), &data);
    if (st == noErr && data) {
        const UInt8 *bytes = CFDataGetBytePtr(data);
        CFIndex len = CFDataGetLength(data);
        addToHistory(std::string((const char *)bytes, (size_t)len));
        CFRelease(data);
    }
}

static void pollPasteboard(CFRunLoopTimerRef, void *) {
    PasteboardSyncFlags flags = PasteboardSynchronize(gPasteboard);
    if (flags & kPasteboardModified) {
        readPasteboardString();
    }
}

// MARK: - Запуск пікера

static void launchPicker() {
    pid_t pid;
    char *argv[] = { (char *)gPickerPath.c_str(), NULL };
    posix_spawn(&pid, gPickerPath.c_str(), NULL, NULL, argv, environ);
}

// MARK: - Глобальний хоткей ⌘⇧V через CGEventTap

static const CGKeyCode kKeyV = 0x09; // kVK_ANSI_V
static CFMachPortRef gTap = NULL;    // для re-enable з колбеку

static CGEventRef hotkeyCallback(CGEventTapProxy, CGEventType type,
                                 CGEventRef event, void *info) {
    // Якщо tap вимкнули (таймаут/дизейбл) — вмикаємо назад.
    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        if (gTap) CGEventTapEnable(gTap, true);
        return event;
    }
    if (type == kCGEventKeyDown) {
        CGKeyCode code = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        CGEventFlags f = CGEventGetFlags(event);
        bool cmd   = f & kCGEventFlagMaskCommand;
        bool shift = f & kCGEventFlagMaskShift;
        bool alt   = f & kCGEventFlagMaskAlternate;
        bool ctrl  = f & kCGEventFlagMaskControl;
        if (code == kKeyV && cmd && shift && !alt && !ctrl) {
            launchPicker();
            return NULL; // поглинаємо ⌘⇧V, щоб не пішло у фронтовий застосунок
        }
    }
    return event;
}

static bool installHotkey() {
    // Accessibility потрібен для CGEventTap — попросимо (з промптом).
    const void *keys[] = { kAXTrustedCheckOptionPrompt };
    const void *vals[] = { kCFBooleanTrue };
    CFDictionaryRef opts = CFDictionaryCreate(NULL, keys, vals, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    bool trusted = AXIsProcessTrustedWithOptions(opts);
    CFRelease(opts);

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    gTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                            kCGEventTapOptionDefault, mask,
                            hotkeyCallback, NULL);
    if (!gTap) {
        fprintf(stderr, "CGEventTapCreate failed (trusted=%d) — хоткей недоступний.\n"
                        "Додай демон у System Settings → Privacy & Security → Accessibility.\n",
                trusted);
        return false;
    }
    CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, gTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
    CGEventTapEnable(gTap, true);
    CFRelease(src);
    return true;
}

int main(int argc, char **argv) {
    gHistoryPath = historyPath();

    // Шлях до пікера поруч із демоном.
    {
        char buf[4096];
        strncpy(buf, argv[0], sizeof(buf) - 1);
        buf[sizeof(buf) - 1] = '\0';
        std::string dir = dirname(buf);
        gPickerPath = dir + "/ClipHistoryCppPicker";
    }

    // Pasteboard
    if (PasteboardCreate(kPasteboardClipboard, &gPasteboard) != noErr) {
        fprintf(stderr, "PasteboardCreate failed\n");
        return 1;
    }
    PasteboardSynchronize(gPasteboard); // базова лінія — не хапаємо поточний вміст

    // Хоткей
    installHotkey();

    // Таймер опитування буфера (0.5s, як у Swift-версії)
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        NULL, CFAbsoluteTimeGetCurrent() + 0.5, 0.5, 0, 0,
        pollPasteboard, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);

    fprintf(stderr, "cpp daemon up, pid=%d\n", getpid());
    CFRunLoopRun();
    return 0;
}
