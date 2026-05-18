# HagimiMonitor OpenSpec

## Purpose
HagimiMonitor is a macOS menu bar hardware monitor with a single cyber cat companion. Hardware metrics are the baseline feature; the differentiated experience is a clear, expressive cat-driven interface that explains system load through animation and short status copy.

The next product purpose is to add lightweight display controls to the same menu bar experience while preserving a compliant App Store build. The Direct distribution build may include non-sandbox display control for brightness, volume, and contrast. The App Store build must remain sandboxed and must exclude non-App-Store-safe display control code and UI.

Display controls should be practical rather than exhaustive: each detected display gets its own compact section with sliders for enabled controls. Sliders show percentage while being adjusted. Settings stay intentionally minimal with four global switches: show built-in displays, enable brightness control, enable volume control, and enable contrast control.

## Product Direction
- Keep the menu bar minimal: one clear cat icon.
- Keep the popover compact: left cat companion, right unified hardware metrics.
- Prioritize readability over raw density.
- Treat CPU, GPU, memory, storage, network, and battery as the core metric set.
- Treat display controls as an optional Direct-build capability, not as part of the App Store feature set.
- Group display controls by display so multiple external monitors remain understandable.
- Show built-in display controls by default in Direct builds, with a setting to hide built-in displays and show only external displays.
- Keep display-control settings to four simple toggles; avoid advanced per-monitor tuning in the initial implementation.
- Support system appearance automatically, including light and dark mode.

## Technical Context
- Platform: macOS SwiftUI menu bar app for Apple Silicon Macs only.
- Visual system: SwiftUI Liquid Glass where available.
- Data sources: Mach host stats, filesystem stats, network interfaces, IOKit power sources, IOKit registry/IOAccelerator for GPU.
- Current UI structure: `MenuBarExtra` label, `MonitorPanelView`, `KittyCatView`, `SystemMonitorSampler`.
- Distribution model: one main branch with separate App Store and Direct targets/schemes. Both app targets are arm64-only. The App Store target keeps `ENABLE_APP_SANDBOX = YES` and excludes display-control implementation files. The Direct target disables App Sandbox, uses Developer ID signing and notarization, and compiles display-control code behind build flags such as `DIRECT_DISTRIBUTION` and `DISPLAY_CONTROL`.
- Display-control reference: `docs/MonitorControl-main` demonstrates display enumeration with `CGGetOnlineDisplayList`, built-in/Apple brightness through DisplayServices, Apple Silicon external display DDC/CI through IOAVService/DCPAVServiceProxy, and VCP commands for brightness, audio speaker volume, mute, and contrast.
- Display-control feasibility: brightness, volume, and contrast are feasible for the Direct build but hardware support varies by monitor, cable, transport, and macOS/Apple Silicon behavior. Unsupported controls should be omitted or disabled per display rather than represented as working sliders.
- App Store constraint: non-sandbox/private display-control paths must not ship in the App Store target. The App Store build should omit display-control UI instead of showing controls that cannot function.
