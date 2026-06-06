#!/usr/bin/env bash
#
# Fetches the binary dependencies that are NOT committed to git, so the project
# can be built from a fresh clone. Run once after cloning:
#
#     ./scripts/bootstrap.sh
#
# The whisper model itself is NOT fetched here — the app downloads it on first
# launch into ~/Library/Application Support/mw/Models/.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_VERSION="v1.7.6"
XCFRAMEWORK_URL="https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_VERSION}/whisper-${WHISPER_VERSION}-xcframework.zip"
DEST="$ROOT/Frameworks/whisper.xcframework"

if [ -d "$DEST" ]; then
  echo "✓ whisper.xcframework already present — nothing to do."
  exit 0
fi

echo "Downloading whisper.cpp xcframework (${WHISPER_VERSION}, Metal-enabled)…"
mkdir -p "$ROOT/Frameworks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fL "$XCFRAMEWORK_URL" -o "$TMP/whisper.zip"
unzip -oq "$TMP/whisper.zip" -d "$TMP"

if [ -d "$TMP/build-apple/whisper.xcframework" ]; then
  mv "$TMP/build-apple/whisper.xcframework" "$DEST"
elif [ -d "$TMP/whisper.xcframework" ]; then
  mv "$TMP/whisper.xcframework" "$DEST"
else
  echo "ERROR: whisper.xcframework not found inside the archive" >&2
  exit 1
fi

echo "✓ Installed → $DEST"
echo "Now open mw.xcodeproj in Xcode 26 and run. The speech model downloads on first launch."
