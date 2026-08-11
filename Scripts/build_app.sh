#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Building KuromiCleans release binary =="
mkdir -p .build
BIN=""
# Prefer a universal (arm64 + x86_64) binary so the app runs on any Mac.
# This toolchain has no SwiftPM, so we compile with swiftc directly.
if swiftc -O -target x86_64-apple-macosx12.0 Sources/SortEngine.swift Sources/main.swift -o .build/KuromiCleans-x86_64 2>/dev/null \
   && swiftc -O -target arm64-apple-macosx12.0 Sources/SortEngine.swift Sources/main.swift -o .build/KuromiCleans-arm64 2>/dev/null; then
    lipo -create -output .build/KuromiCleans .build/KuromiCleans-arm64 .build/KuromiCleans-x86_64
    rm -f .build/KuromiCleans-arm64 .build/KuromiCleans-x86_64
    BIN=".build/KuromiCleans"
    echo "Universal (arm64 + x86_64) binary built."
else
    echo "Universal build not supported here; building native instead."
    swiftc -O Sources/SortEngine.swift Sources/main.swift -o .build/KuromiCleans
    BIN=".build/KuromiCleans"
fi
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
    echo "ERROR: built binary not found." >&2
    exit 1
fi

echo "== Assembling dist/KuromiCleans.app =="
APP="dist/KuromiCleans.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/KuromiCleans"

bash Scripts/make_icon.sh
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>KuromiCleans</string>
	<key>CFBundleDisplayName</key>
	<string>KuromiCleans</string>
	<key>CFBundleIdentifier</key>
	<string>com.kuromicleans.app</string>
	<key>CFBundleExecutable</key>
	<string>KuromiCleans</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSUIElement</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "== Signing =="
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
echo "Signature verified."

echo "== Result =="
file "$APP/Contents/MacOS/KuromiCleans"
echo "Done: $APP"
