## Why

macOS 27 beta changes the practical rendering of SwiftUI Liquid Glass in menu-bar windows: glass rows and `.glass` buttons show stronger highlights, hover treatments, and refractive edges than macOS 26. HagimiMonitor uses glass at the window, row, and button levels, so the dark-mode panel can become visually noisy and less readable on macOS 27.

This proposal records a deferred adaptation plan only. The current macOS 27 release is Beta 1, so implementation should wait until later betas clarify whether the stronger glass behavior is stable.

## What Changes

- Rebalance the monitor panel visual hierarchy for macOS 27 so the system menu-window glass remains the outer shell while metric content keeps a stable, subdued reading surface.
- Reduce or remove Liquid Glass from dense content rows and command buttons when it harms readability or unity.
- Preserve the existing compact layout, metric ordering, module colors, and App Store/Direct target separation.
- Add a compatibility strategy for macOS 26 and macOS 27 if their glass rendering remains materially different.
- Avoid changing sampler behavior, display-control behavior, or settings persistence unless a user-facing appearance option is explicitly needed later.

## Capabilities

### New Capabilities

### Modified Capabilities
- `monitor-panel`: Add requirements for stable dark-mode readability and controlled Liquid Glass usage across macOS 26 and macOS 27.

## Impact

- Affected UI files: `HagimiMonitor/MonitorPanelView.swift`, `HagimiMonitor/MonitorPalette.swift`, and possibly `HagimiMonitor/Constants.swift`.
- Affected direct-build UI: `HagimiMonitorDirectOnly/DisplayControlsSection.swift` if its glass styling needs the same treatment.
- No sampler, entitlement, sandbox, or distribution-model changes are expected.
- Validation should include side-by-side visual review on macOS 26 and macOS 27, especially dark mode over bright and complex desktop backgrounds.
