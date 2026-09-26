#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$source_dir/../.." && pwd)"
output="$root/tmp/game-fps-hook-probe"
mkdir -p "$output/MetalSceneProbe.app/Contents/MacOS" \
    "$output/OpenGLSceneProbe.app/Contents/MacOS" "$output/module-cache"

xcrun clang -std=c11 -fobjc-arc -fblocks -dynamiclib -O2 \
    -mmacosx-version-min=15.0 \
    -framework AppKit -framework Metal -framework QuartzCore -framework OpenGL \
    "$source_dir/PresentObserver.m" -o "$output/libPresentObserver.dylib"
codesign --force --sign - "$output/libPresentObserver.dylib"

xcrun swiftc -swift-version 6 -parse-as-library -O \
    -target "$(uname -m)-apple-macosx15.0" \
    -module-cache-path "$output/module-cache" \
    -framework AppKit -framework MetalKit \
    "$root/prototypes/game-hud-probe/MetalSceneProbe.swift" \
    -o "$output/MetalSceneProbe.app/Contents/MacOS/MetalSceneProbe"
python3 - "$output/MetalSceneProbe.app" <<'PY'
import pathlib
import plistlib
import sys
bundle = pathlib.Path(sys.argv[1])
with (bundle / 'Contents' / 'Info.plist').open('wb') as file:
    plistlib.dump({
        'CFBundleExecutable': 'MetalSceneProbe',
        'CFBundleIdentifier': 'local.hagimi.probe.fps-metal',
        'CFBundleName': 'Hagimi Metal FPS Probe',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'LSMinimumSystemVersion': '15.0',
        'NSHighResolutionCapable': True,
    }, file)
PY
codesign --force --sign - "$output/MetalSceneProbe.app"

xcrun clang -std=c11 -O2 -Wno-deprecated-declarations \
    -mmacosx-version-min=15.0 \
    -I/opt/homebrew/include -L/opt/homebrew/lib \
    -Wl,-rpath,/opt/homebrew/lib \
    "$source_dir/OpenGLSceneProbe.c" -lSDL2 -framework OpenGL \
    -o "$output/OpenGLSceneProbe.app/Contents/MacOS/OpenGLSceneProbe"
python3 - "$output/OpenGLSceneProbe.app" <<'PY'
import pathlib
import plistlib
import sys
bundle = pathlib.Path(sys.argv[1])
with (bundle / 'Contents' / 'Info.plist').open('wb') as file:
    plistlib.dump({
        'CFBundleExecutable': 'OpenGLSceneProbe',
        'CFBundleIdentifier': 'local.hagimi.probe.fps-opengl',
        'CFBundleName': 'Hagimi OpenGL FPS Probe',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'LSMinimumSystemVersion': '15.0',
        'NSHighResolutionCapable': True,
    }, file)
PY
codesign --force --sign - "$output/OpenGLSceneProbe.app"

echo "Built FPS hook probe in $output"
