#!/bin/bash
set -euo pipefail
demo_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$demo_root/../.." && pwd)"
output_root="${1:-$repo_root/tmp/panel-motion-reference}"
mkdir -p "$output_root/source"
tar -xzf "$demo_root/reference/source-baseline.tar.gz" -C "$output_root/source"
python3 "$demo_root/install_native_cpu.py" "$output_root/source"
xcodebuild -project "$output_root/source/hagimi-monitor.xcodeproj" -scheme HagimiMonitorDirect \
  -configuration Release -destination 'platform=macOS' -derivedDataPath "$output_root/derived-data" \
  -clonedSourcePackagesDirPath "$repo_root/tmp/dd-direct/SourcePackages" \
  -disableAutomaticPackageResolution PRODUCT_BUNDLE_IDENTIFIER=local.hagimi.cpu-native-demo \
  CODE_SIGNING_ALLOWED=NO build > "$output_root/build.log" 2>&1
ditto "$output_root/derived-data/Build/Products/Release/HagimiMonitorDirect.app" "$output_root/HagimiCPUNativeDemo.app"
codesign --force --deep --sign - "$output_root/HagimiCPUNativeDemo.app"
echo "Demo: $output_root/HagimiCPUNativeDemo.app"
