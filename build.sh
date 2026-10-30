#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/Build/Rava.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -framework AppKit -framework AVFoundation -lsqlite3 \
  "$ROOT/Sources/DictionaryStore.swift" "$ROOT/Sources/main.swift" \
  -o "$APP/Contents/MacOS/Rava"
cp "$ROOT/Resources/dictionary.sqlite" "$APP/Contents/Resources/dictionary.sqlite"
cp "$ROOT/Resources/Rava.icns" "$APP/Contents/Resources/Rava.icns"
cp "$ROOT/ATTRIBUTION.md" "$APP/Contents/Resources/ATTRIBUTION.md"
cp "$ROOT/WIKDICT_ATTRIBUTION.md" "$APP/Contents/Resources/WIKDICT_ATTRIBUTION.md"
cp "$ROOT/OPENJAM_LICENSE.txt" "$APP/Contents/Resources/OPENJAM_LICENSE.txt"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
echo "Built $APP"
