#!/bin/bash
# Збірка C++ варіанту ClipHistory (демон без AppKit + Obj-C++ пікер).
set -e
cd "$(dirname "$0")"

APP="ClipHistoryCpp.app"
MACOS="$APP/Contents/MacOS"
EXE="ClipHistoryCpp"          # видно в Activity Monitor

rm -rf "$APP"
mkdir -p "$MACOS"

echo "→ Компіляція $EXE (демон, C++, БЕЗ AppKit)…"
clang++ -O2 -std=c++17 daemond.cpp -o "$MACOS/$EXE" \
    -framework ApplicationServices -framework CoreFoundation

echo "→ Компіляція пікера (Objective-C++, AppKit, на вимогу)…"
clang++ -O2 -std=c++17 -ObjC++ -fobjc-arc picker.mm -o "$MACOS/ClipHistoryCppPicker" \
    -framework Cocoa -framework ApplicationServices

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipHistoryCpp</string>
    <key>CFBundleDisplayName</key><string>ClipHistoryCpp</string>
    <key>CFBundleIdentifier</key><string>com.ek.cliphistorycpp</string>
    <key>CFBundleExecutable</key><string>ClipHistoryCpp</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST

# Підпис: той самий стабільний сертифікат, якщо є, інакше ad-hoc.
CERT_NAME="ClipHistory Self-Signed"
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    SIGN="$CERT_NAME"
    echo "→ Підписую «$CERT_NAME»"
else
    SIGN="-"
    echo "⚠️  Сертифіката нема — ad-hoc підпис (Accessibility перепитуватиметься)."
fi

codesign --force --sign "$SIGN" -i com.ek.cliphistorycpp.picker "$MACOS/ClipHistoryCppPicker"
codesign --force --sign "$SIGN" --identifier com.ek.cliphistorycpp "$APP"

echo "✅ Готово: cpp/$APP"
echo "Запуск:   open cpp/$APP"
echo "Зупинка:  pkill ClipHistoryCpp"
