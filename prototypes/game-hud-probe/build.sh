#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$source_dir/../.." && pwd)"
output="$root/tmp/game-hud-probe"
mkdir -p "$output"

for name in OverlayProbe SandboxOverlayProbe MetalSceneProbe; do
    bundle="$output/$name.app"
    mkdir -p "$bundle/Contents/MacOS"
    sources=("$source_dir/OverlayProbe.swift" "$source_dir/ProbeMetrics.swift")
    flags=(-module-name "$name")
    if [[ "$name" == "MetalSceneProbe" ]]; then
        sources=("$source_dir/MetalSceneProbe.swift")
    elif [[ "$name" == "SandboxOverlayProbe" ]]; then
        flags+=(-D SANDBOX_PROBE)
    fi
    xcrun swiftc -swift-version 6 -parse-as-library -O \
        -target "$(uname -m)-apple-macosx15.0" \
        -module-cache-path "$output/module-cache" \
        -framework AppKit -framework MetalKit -framework IOKit -framework Security \
        "${flags[@]}" "${sources[@]}" -o "$bundle/Contents/MacOS/$name"
    python3 - "$bundle" "$name" <<'PY'
import pathlib
import plistlib
import sys
bundle = pathlib.Path(sys.argv[1])
name = sys.argv[2]
values = {
    'CFBundleExecutable': name,
    'CFBundleIdentifier': f'local.hagimi.probe.{name}',
    'CFBundleName': name,
    'CFBundleDisplayName': name,
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '2',
    'CFBundleShortVersionString': '2.0',
    'LSMinimumSystemVersion': '15.0',
    'NSHighResolutionCapable': True,
    'LSUIElement': name != 'MetalSceneProbe',
}
with (bundle / 'Contents' / 'Info.plist').open('wb') as handle:
    plistlib.dump(values, handle)
PY
    if [[ "$name" == "SandboxOverlayProbe" ]]; then
        codesign --force --sign - --entitlements "$source_dir/SandboxOverlayProbe.entitlements" "$bundle"
    else
        codesign --force --sign - "$bundle"
    fi
done
printf 'Built probes in %s\n' "$output"
printf 'Sandbox HUD: open "%s/SandboxOverlayProbe.app"\n' "$output"
printf 'Scene without official HUD: "%s/MetalSceneProbe.app/Contents/MacOS/MetalSceneProbe" --no-hud --auto-fullscreen\n' "$output"
printf 'Native scene controls: F fullscreen, B borderless, A activate, 1/2 cap, Q quit.\n'
