#!/bin/bash
# Installs SnowDesk into /Applications.
# Usage: curl -fsSL https://github.com/arvind-m-dev/SnowDesk/releases/latest/download/install.sh | bash
set -euo pipefail

URL="https://github.com/arvind-m-dev/SnowDesk/releases/latest/download/SnowDesk.zip"
DEST="/Applications"

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then
  echo "SnowDesk needs macOS 14 (Sonoma) or newer. This Mac has $(sw_vers -productVersion)." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading SnowDesk..."
curl -fsSL "$URL" -o "$tmp/SnowDesk.zip"
ditto -x -k "$tmp/SnowDesk.zip" "$tmp"

pkill -x SnowDesk 2>/dev/null || true
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
rm -rf "$DEST/SnowDesk.app"
mv "$tmp/SnowDesk.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/SnowDesk.app" 2>/dev/null || true

echo "Installed to $DEST/SnowDesk.app"
open "$DEST/SnowDesk.app"
