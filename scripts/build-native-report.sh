#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 项目内选择 SDK，不改变用户的全局 xcode-select 配置。
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]] || [[ "$(xcrun --sdk macosx --show-sdk-version | cut -d. -f1)" -lt 27 ]]; then
  echo 'This report requires Xcode 27 or later. Set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-appstore build
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-direct build
