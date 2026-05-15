# HagimiMonitor OpenSpec

## Purpose
HagimiMonitor is a macOS menu bar hardware monitor with a single cyber cat companion. Hardware metrics are the baseline feature; the differentiated experience is a clear, expressive cat-driven interface that explains system load through animation and short status copy.

## Product Direction
- Keep the menu bar minimal: one clear cat icon.
- Keep the popover compact: left cat companion, right unified hardware metrics.
- Prioritize readability over raw density.
- Treat CPU, GPU, memory, storage, network, and battery as the core metric set.
- Support system appearance automatically, including light and dark mode.

## Technical Context
- Platform: macOS SwiftUI menu bar app.
- Visual system: SwiftUI Liquid Glass where available.
- Data sources: Mach host stats, filesystem stats, network interfaces, IOKit power sources, IOKit registry/IOAccelerator for GPU.
- Current UI structure: `MenuBarExtra` label, `MonitorPanelView`, `KittyCatView`, `SystemMonitorSampler`.

