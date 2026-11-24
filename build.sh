#!/bin/zsh
# Builds MiniDeck.app in this folder. Usage: ./build.sh [--install]
set -euo pipefail
cd "${0:A:h}"
VERSION=$(<VERSION)   # the one place the version lives; release.sh sets it
# Universal binary (Apple Silicon + Intel); each arch needs its own build folder.
ARM=(-c release --triple arm64-apple-macosx14.0 --scratch-path .build-arm64)
X86=(-c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86)
swift build $ARM
swift build $X86
# Ask Swift where it put each binary (the folder differs between Swift versions).
ARM_BIN=$(swift build $ARM --show-bin-path)/MiniDeck
X86_BIN=$(swift build $X86 --show-bin-path)/MiniDeck
APP=MiniDeck.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp icon/AppIcon.icns $APP/Contents/Resources/AppIcon.icns   # remake with: swift icon/make-icon.swift
lipo -create "$ARM_BIN" "$X86_BIN" \
  -output $APP/Contents/MacOS/MiniDeck
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.minideck</string>
  <key>CFBundleName</key><string>MiniDeck</string>
  <key>CFBundleExecutable</key><string>MiniDeck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><false/>
  <key>NSAppleEventsUsageDescription</key><string>MiniDeck controls Music.app (play, pause, skip, playlists).</string>
</dict></plist>
PLIST
codesign --force -s - $APP
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications && rm -rf ~/Applications/$APP && cp -R $APP ~/Applications/
  echo "Installed to ~/Applications/$APP"
fi
mkdir -p dist && rm -f dist/MiniDeck.zip && ditto -c -k --keepParent $APP dist/MiniDeck.zip
echo "Built $PWD/$APP and dist/MiniDeck.zip"
