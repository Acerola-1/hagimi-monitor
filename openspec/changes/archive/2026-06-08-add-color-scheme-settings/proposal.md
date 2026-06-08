## Why

The monitor panel now has a calmer neutral blue-gray visual system, but the earlier colorful panel remains a recognizable part of HagimiMonitor's identity. Users should be able to choose between the current balanced look and a more vibrant module-tinted look without the view code regressing to hardcoded color branches.

## What Changes

- Add a color scheme setting under Settings -> General -> Appearance.
- Default to the current balanced palette.
- Add a vibrant palette that restores the spirit of the original colorful panel while keeping the current layout and typography rules.
- Introduce a palette abstraction so panel colors, module accents, display controls, and severity colors are resolved from a single source.
- Keep severity colors as an independent semantic layer, not derived from module colors.
- Keep Settings appearance itself following the system appearance; this change controls the monitor panel palette, not the app-wide light/dark mode.

## Capabilities

### New Capabilities
- `color-scheme-settings`: User-facing selection, persistence, and default behavior for monitor panel color schemes.

### Modified Capabilities
- `monitor-panel`: The panel must render from a selected palette and support both balanced neutral surfaces and vibrant module-tinted surfaces.

## Impact

- Affected files are expected to include `MonitorSettings.swift`, `SettingsView.swift`, `MonitorPanelView.swift`, `ProgressMeter.swift`, `MonitorModels.swift`, and `HagimiMonitorDirectOnly/DisplayControlsSection.swift`.
- No new runtime dependency is expected.
- Existing user settings should migrate by defaulting missing color scheme values to the balanced palette.
- The Direct display-control target must use the same palette source as the main monitor panel.
