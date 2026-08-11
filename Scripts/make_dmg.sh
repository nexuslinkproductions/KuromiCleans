#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "dist/KuromiCleans.app" ]; then
    echo "dist/KuromiCleans.app not found. Run Scripts/build_app.sh first." >&2
    exit 1
fi

echo "== Staging DMG contents =="
STAGE="dist/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "dist/KuromiCleans.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "== Creating dist/KuromiCleans.dmg =="
rm -f "dist/KuromiCleans.dmg"
hdiutil create -volname KuromiCleans -srcfolder "$STAGE" -ov -format UDZO "dist/KuromiCleans.dmg"
rm -rf "$STAGE"

echo "== Verifying DMG =="
hdiutil detach "/Volumes/KuromiCleans" >/dev/null 2>&1 || true
MOUNT="$(hdiutil attach -nobrowse "dist/KuromiCleans.dmg" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
if [ -z "$MOUNT" ]; then
    echo "ERROR: could not mount the DMG." >&2
    exit 1
fi
echo "Mounted at: $MOUNT"
ls -la "$MOUNT"
test -d "$MOUNT/KuromiCleans.app"
test -L "$MOUNT/Applications"
hdiutil detach "$MOUNT"

echo "Done: dist/KuromiCleans.dmg (verified)"
