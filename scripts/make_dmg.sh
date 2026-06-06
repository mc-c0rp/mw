#!/usr/bin/env bash
#
# Builds an installer .dmg (the app + an Applications drop-link) with a custom
# volume/file icon rendered from dmg.svg.
#
#   ./scripts/make_dmg.sh <path-to-mw.app> <version>
#
# Output: dist/mw-<version>.dmg
#
# Requires: create-dmg (brew install create-dmg).

set -euo pipefail

APP="${1:?usage: make_dmg.sh <mw.app> <version>}"
VERSION="${2:?usage: make_dmg.sh <mw.app> <version>}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/dmg.svg"
OUT="$ROOT/dist"
DMG="$OUT/mw-$VERSION.dmg"
mkdir -p "$OUT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Render dmg.svg → .icns
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/$(basename "$SVG").png"
[ -f "$MASTER" ] || { echo "ERROR: could not render $SVG" >&2; exit 1; }
ICONSET="$TMP/dmg.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
ICNS="$TMP/dmg.icns"
iconutil -c icns "$ICONSET" -o "$ICNS"

# 2) Stage just the app
STAGE="$TMP/stage"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# 3) Build the DMG (app on the left, Applications on the right)
rm -f "$DMG"
create-dmg \
  --volname "mw $VERSION" \
  --volicon "$ICNS" \
  --window-pos 200 120 \
  --window-size 540 380 \
  --icon-size 110 \
  --icon "mw.app" 150 185 \
  --hide-extension "mw.app" \
  --app-drop-link 390 185 \
  --no-internet-enable \
  "$DMG" "$STAGE"

[ -f "$DMG" ] || { echo "ERROR: DMG was not created" >&2; exit 1; }

# 4) Also set the custom icon on the .dmg file itself (NSWorkspace is reliable)
osascript - "$ICNS" "$DMG" >/dev/null 2>&1 <<'OSA' || true
use framework "AppKit"
on run argv
  set img to current application's NSImage's alloc()'s initWithContentsOfFile:(item 1 of argv)
  current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:(item 2 of argv) options:0
end run
OSA

echo "Created $DMG"
du -h "$DMG"
