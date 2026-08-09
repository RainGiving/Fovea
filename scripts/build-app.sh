#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/Fovea.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LOCALIZATION_BUNDLE="$ROOT_DIR/.build/release/Fovea_FoveaApp.bundle"

swift build --disable-sandbox --configuration release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/Fovea" "$MACOS_DIR/Fovea"
cp "$ROOT_DIR/Sources/FoveaApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/FoveaApp/Resources/Fovea.icns" "$RESOURCES_DIR/Fovea.icns"
cp -R "$LOCALIZATION_BUNDLE" "$RESOURCES_DIR/Fovea_FoveaApp.bundle"
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
chflags nohidden "$APP_DIR"

echo "$APP_DIR"
