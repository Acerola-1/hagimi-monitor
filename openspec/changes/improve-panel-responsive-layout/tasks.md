## 1. Audit Current Panel Layout

- [x] 1.1 Review `MonitorPanelView.swift` for remaining adaptable text using fixed point-size fonts.
- [x] 1.2 Review `DisplayControlsSection.swift` for fixed text sizes, fixed text containers, and truncation behavior.
- [x] 1.3 Classify fixed frames as intentional visual geometry or content containers that should become flexible.

## 2. Shared Panel Primitives

- [x] 2.1 Finalize panel width constants for minimum, ideal, and maximum width in `MonitorConstants`.
- [x] 2.2 Centralize panel text helpers around semantic SwiftUI `Font.TextStyle` values.
- [x] 2.3 Document fixed geometry conventions in code only where the intent is not obvious.

## 3. Main Panel Responsive Layout

- [x] 3.1 Update metric row labels, values, captions, buttons, and pills to use shared semantic text helpers.
- [x] 3.2 Adjust expanded metric details so long labels and values use explicit truncation, scaling, or single-column layout as appropriate.
- [x] 3.3 Verify network, battery, storage, CPU, GPU, and memory rows remain aligned in collapsed and expanded states.
- [x] 3.4 Add or preserve copy/help behavior for long values that may be truncated.

## 4. Direct Display Controls Layout

- [x] 4.1 Update display control row typography to match main panel semantic text helpers.
- [x] 4.2 Replace fixed point-size display labels, summaries, badges, and slider labels with adaptive text styles.
- [x] 4.3 Ensure long display names truncate without hiding badges, sliders, or current values.
- [x] 4.4 Keep slider and icon geometry stable where fixed dimensions are intentional.

## 5. Verification

- [x] 5.1 Run `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug build`.
- [x] 5.2 Run `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build`.
- [x] 5.3 Run relevant tests with `xcodebuild test -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -destination 'platform=macOS'` if test runtime is available.
- [ ] 5.4 Manually verify collapsed and expanded panel states with long network values, long storage names, localized labels, and enabled display controls.
