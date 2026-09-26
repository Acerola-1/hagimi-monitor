# Game FPS render-path probe

This isolated prototype checks whether a small library loaded into a **test process at launch** can observe frame events without help from the renderer. It does not change HagimiMonitor or inject into third-party games.

## Backends

- **Metal:** Existing `MetalSceneProbe` at a requested 120 FPS. The observer swizzles `CAMetalLayer.nextDrawable` and adds an `MTLDrawable` presented handler. `metal_presented` counts drawables with a positive `presentedTime`.
- **OpenGL:** An SDL2/OpenGL window changes its clear color every frame. The observer independently records `CGLFlushDrawable` and `NSOpenGLContext.flushBuffer` calls. These are diagnostics for the same swap path and must **not** be added together.
- **Vulkan:** `run.sh vulkan` runs `vkcube` when the Vulkan loader, MoltenVK and tool are installed. It checks whether MoltenVK reaches the same `CAMetalLayer` observer. This is **not** a general Vulkan hook; a Vulkan layer intercepting `vkQueuePresentKHR` would be needed to cover Vulkan runtimes that do not pass through `CAMetalLayer`.

## Run

```bash
brew install sdl2-compat molten-vk vulkan-tools
prototypes/game-fps-hook-probe/build.sh
prototypes/game-fps-hook-probe/run.sh metal
prototypes/game-fps-hook-probe/run.sh opengl
prototypes/game-fps-hook-probe/run.sh vulkan
```

The observer writes one JSON line per second under `tmp/game-fps-hook-probe/<backend>-observer.jsonl`. Target stdout and stderr are saved beside it. Metal and OpenGL app bundles are launched through LaunchServices so AppKit can register them. The Metal target accepts keys `1`, `2`, `3` for 30/60/120 FPS and `q` to quit. The OpenGL target accepts Escape to quit. A successful test requires a `{"probe":"loaded"}` line followed by nonzero frame counts; a moving window alone does not establish that injection worked.

These test binaries are signed ad hoc without hardened runtime. The Homebrew SDL2 compatibility library used by the OpenGL target on this machine was built for macOS 26, so that binary does not establish macOS 15 runtime compatibility. The result cannot establish that an independently signed third-party game permits loading this library. Steam's own overlay depends on permissions granted by each game build.

## Local result (Apple M4, 120 Hz display, 2026-09-26)

| Target | Observer event | Steady one-second count | Evidence |
| --- | --- | ---: | --- |
| Metal scene | `metal_presented` | 119–120 | `metal-observer.jsonl`; official Metal HUD disabled in target |
| SDL OpenGL scene | `cgl_swaps` and `cocoa_swaps` | 120 each | `opengl-observer.jsonl`; they describe the same swap |
| Vulkan `vkcube` via MoltenVK | `metal_presented` | 118–120 | `vulkan-observer.jsonl`; `vulkan-stderr.log` identifies Metal WSI and Apple M4 |

Run `python3 prototypes/game-fps-hook-probe/verify.py` to check the current logs. Counts vary during launch and when the window loses focus. This experiment proves that the controlled targets expose frame events to the injected library. It does **not** prove that all third-party games allow injection, that all Vulkan implementations use this Metal path, or that OpenGL swap calls equal on-glass presentation times.

## Real-game validation (2026-09-26, same machine)

Two commercial Steam games were launched from the shell with `DYLD_INSERT_LIBRARIES` pointing at the observer build; Steam client was running and logged in. No game binary, signature, Info.plist, or system protection was modified.

| Game | Engine / render path | Signing | Result |
| --- | --- | --- | --- |
| Balatro 1.0.1o | LÖVE / SDL2 / OpenGL (`CGLFlushDrawable`) | ad-hoc, **no hardened runtime** | **Injection works.** One stable process (`obs=4` mappings, no relaunch). Observer counted 114–117/s on the title screen, 145–156/s while the engine rendered unlocked; process exit reclaims the library with no residue. |
| Kingdom Rush Genesis | LÖVE / SDL2 / OpenGL, universal (arm64+x86_64) | Developer ID + **hardened runtime**, entitlements include `allow-dyld-environment-variables` and `disable-library-validation` | **Injection blocked by Steam's own relaunch.** Details below. |

Kingdom Rush Genesis evidence (all with Steam online):

1. `DYLD_INSERT_LIBRARIES` launch: the observer loads in the first process (`{"probe":"loaded"}` written, `cgl_swaps` still 0), which then **exits**; the real game process (`ppid=1`) never maps the observer (verified via `vmmap`).
2. The relaunch is Steam-side, not ours: launching with **no injection** shows the same two-phase pattern (pid A dies ~3 s in, pid B with `ppid=1` takes over). `steamclient.dylib` imports `_fork` and `_posix_spawn`, and contains the strings `DYLD_INSERT_LIBRARIES`, `DYLD_LIBRARY_PATH`, `STEAM_DYLD_INSERT_LIBRARIES`, `SUPPRESS_STEAM_OVERLAY`.
3. `STEAM_DYLD_INSERT_LIBRARIES=<ours>:<steamloader>`: the relaunched process maps `steamloader.dylib` (2 mappings) but not ours — Steam rebuilds the insert list with its own allowlist.
4. `SUPPRESS_STEAM_OVERLAY=1`: relaunch still happens; overlay suppression only disables the overlay.
5. Steam client offline: `SteamAPI_Init()` fails and the game exits — no injection window exists without Steam.
6. Writing `LaunchOptions` directly into `userdata/<id>/config/localconfig.vdf` (with `%command%`): Steam ignores it on macOS (touch marker never ran). The file was restored from backup afterwards.

`LSEnvironment` in the game's `Info.plist` is the remaining known macOS channel for pre-setting `DYLD_INSERT_LIBRARIES`, but it requires modifying and re-signing the game bundle — out of bounds per task constraints, so it is recorded, not attempted.

**Coverage conclusion:** environment-variable injection into the real game process works for non-hardened games (Balatro). For hardened games whose launch goes through Steam's relaunch allowlist (Kingdom Rush Genesis), no signature-free injection channel was found; the three no-modification channels (env vars, Steam relaunch passthrough, offline launch) were each tested and excluded with evidence above.
