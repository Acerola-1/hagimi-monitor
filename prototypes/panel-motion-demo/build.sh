#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
demo_root="$repo_root/prototypes/panel-motion-demo"
app_root="$repo_root/tmp/panel-motion-demo/HagimiMotionDemo.app"
mkdir -p "$app_root/Contents/MacOS" "$app_root/Contents/Resources" "$repo_root/tmp/panel-motion-demo/module-cache"
python3 "$demo_root/prepare_skin.py" "$repo_root" "$repo_root/tmp/panel-motion-demo/Palette.generated.swift"
cp "$demo_root/Demo.swift" "$repo_root/tmp/panel-motion-demo/main.swift"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx15.0 \
  -module-cache-path "$repo_root/tmp/panel-motion-demo/module-cache" \
  "$repo_root/tmp/panel-motion-demo/main.swift" "$repo_root/tmp/panel-motion-demo/Palette.generated.swift" \
  "$repo_root/HagimiMonitor/Constants.swift" -o "$app_root/Contents/MacOS/HagimiMotionDemo" \
  -framework AppKit -framework SwiftUI -framework QuartzCore
cp "$demo_root/snapshot.json" "$app_root/Contents/Resources/snapshot.json"
cat > "$app_root/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HagimiMotionDemo</string>
<key>CFBundleIdentifier</key><string>local.hagimi.motion-demo</string>
<key>CFBundleName</key><string>Hagimi Motion Demo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_root"
printf '%s\n' "$app_root"
