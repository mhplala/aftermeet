#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/.build/Build/Products/Debug/AfterMeet.app}"
IDENTITY="${AFTERMEET_SIGNING_IDENTITY:-9E96E6F329CAC93BD47EBD01100ABD51C32A4D1B}"
ENTITLEMENTS="$ROOT/Aftermeet.entitlements"
REQUIREMENTS="$ROOT/AfterMeet.requirements"

if [[ ! -d "$APP" ]]; then
  printf 'App not found: %s\n' "$APP" >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  printf 'Developer ID identity not found: %s\n' "$IDENTITY" >&2
  exit 1
fi

TIMESTAMP=(--timestamp=none)
if [[ "${AFTERMEET_SIGN_TIMESTAMP:-0}" == "1" ]]; then
  TIMESTAMP=(--timestamp)
fi

codesign \
  --force \
  --strict \
  --options runtime \
  "${TIMESTAMP[@]}" \
  --entitlements "$ENTITLEMENTS" \
  --requirements "$REQUIREMENTS" \
  --sign "$IDENTITY" \
  "$APP"

codesign --verify --deep --strict --verbose=1 "$APP"
expected="$(tr -d '\n' < "$REQUIREMENTS")"
actual="$(codesign -d -r- "$APP" 2>&1 | grep '^designated')"
if [[ "$actual" != "$expected" ]]; then
  printf 'Designated requirement mismatch.\nExpected: %s\nActual:   %s\n' "$expected" "$actual" >&2
  exit 1
fi

printf 'Signed and verified: %s\n' "$APP"
