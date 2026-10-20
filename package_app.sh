#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

echo "🔨 Compiling FlowWidget native binary..."
mkdir -p ./cache
swiftc -module-cache-path ./cache FlowWidget.swift -o FlowWidget -framework Cocoa -framework AVFoundation -framework Speech -framework Carbon

echo "📦 Creating FlowWidget.app macOS Application Bundle..."
APP_BUNDLE="FlowWidget.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"
cp FlowWidget "$MACOS/FlowWidget"
chmod +x "$MACOS/FlowWidget"
cp Info.plist "$CONTENTS/Info.plist"

echo "🔐 Ad-hoc code signing FlowWidget.app with bundle ID..."
codesign -s - --force --deep --identifier "com.local.flowwidget" "$APP_BUNDLE"

echo "✅ Successfully built & signed FlowWidget.app!"
echo "👉 You can launch it with: open ./FlowWidget.app"
