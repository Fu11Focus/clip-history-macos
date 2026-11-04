#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="ClipHistory.app"
MACOS="$APP/Contents/MacOS"
EXE="ClipHistory"          # ← ім'я, що видно в Activity Monitor / Login Items

# Приберемо стару GUI-збірку, щоб не плутатись
rm -rf "ClipHistoryd.app"
rm -rf "$APP"
mkdir -p "$MACOS"

echo "→ Компіляція $EXE (демон, без AppKit)…"
swiftc -O daemon.swift -o "$MACOS/$EXE" \
    -framework ApplicationServices -framework Carbon

echo "→ Компіляція picker (AppKit, запускається на вимогу)…"
swiftc -O picker.swift -o "$MACOS/ClipHistoryPicker" \
    -framework Cocoa -framework Carbon

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipHistory</string>
    <key>CFBundleDisplayName</key><string>ClipHistory</string>
    <key>CFBundleIdentifier</key><string>com.ek.cliphistory</string>
    <key>CFBundleExecutable</key><string>ClipHistory</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "✅ Готово: $APP"
echo "   $EXE              — резидентний демон (~3.5 МБ), видно як «ClipHistory»"
echo "   ClipHistoryPicker — на вимогу (~16 МБ лише поки видно)"
echo
echo "Запуск:   open $APP"
echo "Зупинка:  pkill ClipHistory"