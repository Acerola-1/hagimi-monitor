#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$source_dir/../.." && pwd)"
output="$root/tmp/game-fps-hook-probe"
backend="${1:-}"
if [[ "$backend" != metal && "$backend" != opengl && "$backend" != vulkan ]]; then
    echo "Usage: $0 metal|opengl|vulkan" >&2
    exit 2
fi
if [[ ! -f "$output/libPresentObserver.dylib" ]]; then
    "$source_dir/build.sh"
fi
log="$output/${backend}-observer.jsonl"
: > "$log"
echo "Observer log: $log"
case "$backend" in
    metal)
        open -n -W -a "$output/MetalSceneProbe.app" \
            --stdout "$output/metal-target.jsonl" --stderr "$output/metal-stderr.log" \
            --env "DYLD_INSERT_LIBRARIES=$output/libPresentObserver.dylib" \
            --env "HAGIMI_FPS_PROBE_LOG=$log" --env HAGIMI_FPS_TARGET=120 \
            --args --no-hud
        ;;
    opengl)
        open -n -W -a "$output/OpenGLSceneProbe.app" \
            --stdout "$output/opengl-target.jsonl" --stderr "$output/opengl-stderr.log" \
            --env "DYLD_INSERT_LIBRARIES=$output/libPresentObserver.dylib" \
            --env "HAGIMI_FPS_PROBE_LOG=$log" --env HAGIMI_FPS_TARGET=120
        ;;
    vulkan)
        if ! command -v brew >/dev/null 2>&1; then
            echo "Vulkan test requires vkcube, Vulkan loader, and MoltenVK." >&2
            exit 3
        fi
        vulkan_app="$(brew --prefix vulkan-tools)/cube/vkcube.app"
        if [[ ! -d "$vulkan_app" ]]; then
            echo "Missing $vulkan_app; install vulkan-tools and molten-vk." >&2
            exit 3
        fi
        open -n -W -a "$vulkan_app" \
            --stdout "$output/vulkan-target.log" --stderr "$output/vulkan-stderr.log" \
            --env "DYLD_INSERT_LIBRARIES=$output/libPresentObserver.dylib" \
            --env "HAGIMI_FPS_PROBE_LOG=$log"
        ;;
esac
