#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output="$root/tmp/accessory-ui-preview"
app="$output/AccessoryDetailsPreview.app"
mkdir -p "$app/Contents/MacOS" "$output/module-cache"
/usr/bin/xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 -module-cache-path "$output/module-cache" -framework SwiftUI -framework AppKit \
  "$root/HagimiMonitor/Constants.swift" "$root/HagimiMonitor/MonitorPalette.swift" \
  "$root/prototypes/accessory-details/Support.swift" "$root/prototypes/accessory-details/Preview.swift" \
  -o "$app/Contents/MacOS/AccessoryDetailsPreview"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.acerola.hagimi-monitor.accessory-preview</string><key>CFBundleExecutable</key><string>AccessoryDetailsPreview</string><key>CFBundleName</key><string>AccessoryDetailsPreview</string><key>LSMinimumSystemVersion</key><string>15.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$app"
