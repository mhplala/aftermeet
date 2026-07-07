#!/usr/bin/env bash
# Release 构建 → Developer ID 签名(硬化运行时) → DMG → 公证 → staple
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-0.2.0}"
IDENTITY="Developer ID Application: Stev Wang (UK68KKX58X)"
APP_NAME="Aftermeet"
DIST="dist"

echo "▸ xcodegen + Release 构建"
xcodegen generate
xcodebuild \
  -project AfterMeet.xcodeproj \
  -scheme AfterMeet \
  -configuration Release \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  build | tail -3

APP_SRC="$(find .build/Build/Products/Release -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP_SRC" ] || { echo "找不到 Release .app"; exit 1; }

rm -rf "$DIST"; mkdir -p "$DIST"
cp -R "$APP_SRC" "$DIST/$APP_NAME.app"

echo "▸ codesign（硬化运行时 + 麦克风 entitlement）"
codesign --force --options runtime --timestamp \
  --entitlements Aftermeet.entitlements \
  --sign "$IDENTITY" \
  "$DIST/$APP_NAME.app"
codesign --verify --strict --verbose=2 "$DIST/$APP_NAME.app"

echo "▸ 制作 DMG"
STAGE="$DIST/stage"; mkdir -p "$STAGE"
cp -R "$DIST/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "▸ 公证（keychain profile: siku）"
xcrun notarytool submit "$DMG" --keychain-profile siku --wait

echo "▸ staple"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✅ $DMG"
