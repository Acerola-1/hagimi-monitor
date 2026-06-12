## Why

The monitor panel currently mixes fixed panel width, fixed point sizes, and content-specific layout workarounds, which makes it fragile across display sizes, system text settings, localization lengths, and optional direct-build display controls. A recent partial responsive update improves the main metrics area, but the panel still needs a consistent layout contract so future modules do not regress into clipped or cramped UI.

## What Changes

- Define responsive sizing behavior for the monitor panel, including minimum, ideal, and maximum widths.
- Standardize panel typography on semantic SwiftUI text styles instead of fixed point sizes where text needs to adapt.
- Preserve fixed dimensions only for intentional control geometry such as icons, sparklines, progress bars, and compact badges.
- Adjust metric detail layouts so long values, network identifiers, disk names, localized labels, and display-control content remain readable or intentionally truncated.
- Apply the same layout and typography rules to the direct-build display controls section when it appears in the panel.
- Add focused tests or verification coverage for representative panel content states.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `monitor-panel`: The panel must provide responsive width, typography, and truncation behavior across metric rows, expanded details, and optional display controls.

## Impact

- Affected app code: `HagimiMonitor/MonitorPanelView.swift`, `HagimiMonitor/Constants.swift`, panel helper views, and direct-build display control UI in `HagimiMonitorDirectOnly/DisplayControlsSection.swift`.
- Affected tests: focused XCTest or UI verification for layout-related formatting helpers and representative panel states where practical.
- No new runtime dependencies or public APIs are expected.
