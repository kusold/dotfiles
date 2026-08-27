#!/bin/bash
# Rebuild InputLevel.app from inputlevel.swift.
#
# The bundle, not the bare binary, is what macOS keys the microphone grant to, so the
# Info.plist below is load-bearing: without NSMicrophoneUsageDescription the request is
# refused with no prompt, which is exactly how Hammerspoon itself fails. The ad-hoc
# signature gives the bundle a stable identity for that grant; re-signing after any
# rebuild is required or the grant is invalidated.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../InputLevel.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

swiftc -O "$here/inputlevel.swift" -o "$app/Contents/MacOS/inputlevel"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>org.kusold.InputLevelHelper</string>
	<key>CFBundleName</key>
	<string>InputLevel</string>
	<key>CFBundleExecutable</key>
	<string>inputlevel</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSBackgroundOnly</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>InputLevel reads your microphone's peak level to show clipping on a Stream Deck touch strip. Audio is never recorded or stored.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null 2>&1
echo "built $app"
