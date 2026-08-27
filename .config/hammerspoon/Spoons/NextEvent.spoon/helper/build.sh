#!/bin/bash
# Rebuild NextEvent.app from nextevent.swift.
#
# The bundle, not the bare binary, is what macOS keys the calendar grant to, so the
# Info.plist below is load-bearing: without NSCalendarsFullAccessUsageDescription the
# request is refused with no prompt, which is exactly how Hammerspoon itself fails.
# The ad-hoc signature gives the bundle a stable identity for that grant; re-signing
# after any rebuild is required or the grant is invalidated.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../NextEvent.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

swiftc -O "$here/nextevent.swift" -o "$app/Contents/MacOS/nextevent"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>org.kusold.NextEventHelper</string>
	<key>CFBundleName</key>
	<string>NextEvent</string>
	<key>CFBundleExecutable</key>
	<string>nextevent</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSBackgroundOnly</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>NextEvent reads your calendar to show the next event on a Stream Deck key.</string>
	<key>NSCalendarsUsageDescription</key>
	<string>NextEvent reads your calendar to show the next event on a Stream Deck key.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null 2>&1
echo "built $app"
