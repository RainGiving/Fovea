#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT_DIR/Sources/FoveaApp/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
APP_NAME="Fovea"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
ARTIFACT_DIR="$ROOT_DIR/.build/artifacts"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging/$APP_NAME"
DMG_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.dmg"

"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$ARTIFACT_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
