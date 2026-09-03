#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ generating Xcode project"
xcodegen generate

echo "▸ building signed app (Debug)"
xcodebuild \
  -project AfterMeet.xcodeproj \
  -scheme AfterMeet \
  -configuration Debug \
  -derivedDataPath .build \
  build | tail -8

APP="$(find .build/Build/Products -maxdepth 3 -name 'AfterMeet.app' | head -1)"
./scripts/sign-local.sh "$APP"
echo "▸ built: $APP"
