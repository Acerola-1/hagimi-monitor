#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 项目内选择 SDK，不改变用户的全局 xcode-select 配置。
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  CURRENT_SDK_VER=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null | cut -d. -f1 || echo 0)
  if [[ "$CURRENT_SDK_VER" -ge 27 ]]; then
    export DEVELOPER_DIR="$(xcode-select -p)"
  elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  fi
fi

if [[ -z "${DEVELOPER_DIR:-}" ]] || [[ ! -d "$DEVELOPER_DIR" ]] || [[ "$(xcrun --sdk macosx --show-sdk-version | cut -d. -f1)" -lt 27 ]]; then
  echo 'This report requires Xcode 27 or later. Set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-appstore build
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-direct build
