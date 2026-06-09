## 1. Beta Validation

- [ ] 1.1 Re-test the current panel on a later macOS 27 beta or release candidate in light and dark mode.
- [ ] 1.2 Capture comparison screenshots on macOS 26 and macOS 27 over plain, bright, and visually complex backgrounds.
- [ ] 1.3 Confirm whether `.glass`, `.glassProminent`, and `.glassEffect` still render with stronger highlights outside toolbars on the later macOS 27 build.
- [ ] 1.4 Decide whether the implementation should use a shared subdued style for all supported systems or an availability-gated macOS 27 variant.

## 2. Panel Surface Strategy

- [ ] 2.1 Remove any full-panel SwiftUI glass or material layer that competes with the `MenuBarExtra(.window)` shell.
- [ ] 2.2 Add or tune an inset reading surface that improves dark-mode contrast without touching the outer window corners.
- [ ] 2.3 Move reading-surface opacity, inset, and corner constants into `MonitorPalette` or `MonitorConstants`.
- [ ] 2.4 Verify the panel corners read as a single coherent shell on macOS 26 and macOS 27.

## 3. Metric Row Styling

- [ ] 3.1 Replace per-row `.glassEffect` styling with subdued palette-driven row fills if macOS 27 row glass remains visually dominant.
- [ ] 3.2 Preserve module accent colors, severity colors, chart colors, progress tracks, and the current compact row layout.
- [ ] 3.3 Keep row hover or click affordance subtle for expandable rows.
- [ ] 3.4 Apply the same row-surface strategy to Direct-build display controls if their glass styling becomes too prominent.

## 4. Command Button Styling

- [ ] 4.1 Replace `.buttonStyle(.glass)` on Activity Monitor and Settings with a quiet custom panel button style if macOS 27 highlights dominate the panel.
- [ ] 4.2 Ensure command buttons remain keyboard-accessible and visually clickable.
- [ ] 4.3 Verify button labels and icons remain readable in light and dark mode.

## 5. Verification

- [ ] 5.1 Build the App Store target with `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug build`.
- [ ] 5.2 Build the Direct target with `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build`.
- [ ] 5.3 Run visual checks on macOS 26 and macOS 27 in dark mode over bright and complex backgrounds.
- [ ] 5.4 Confirm the App Store target still excludes Direct-only display-control UI.
