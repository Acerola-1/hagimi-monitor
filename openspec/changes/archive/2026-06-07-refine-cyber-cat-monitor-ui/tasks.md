# Tasks

## 1. Layout Polish
- [x] Center the left cat column inside the popover.
- [x] Reposition the speech bubble above the cat with balanced width and spacing.
- [x] Verify the cat, bubble, and label feel like one visual unit.

## 2. Menu Bar Icon
- [x] Redraw `MenuBarCatIcon` with a stronger small-size silhouette.
- [x] Add appearance-aware colors for light/dark mode.
- [x] Verify icon clarity at native menu bar size.

## 3. Metric Formatting
- [x] Remove all primary `使用中` suffixes.
- [x] Format primary labels as `CPU: 80%`, `GPU: 68%`, `内存: 62%`, etc.
- [x] Normalize secondary metric font size and weight across rows.

## 4. Metric Content
- [x] Remove GPU temperature from the UI.
- [x] Translate `Tiler` to `分块`.
- [x] Rename memory primary label from pressure to usage.
- [x] Replace memory pressure text with numeric pressure/usage value instead of `正常`.
- [x] Remove memory `App` and `压缩` fields.
- [x] Add swap memory to memory secondary metrics.
- [x] Limit network secondary metrics to upload and download.
- [x] Show sparklines only for CPU and GPU.
- [x] Add expandable GPU, memory, and storage detail rows.
- [x] Show GPU memory, memory pressure, and storage used/total values in expanded details.
- [x] Add expandable CPU details with system, user, idle, and boot time values.
- [x] Pull `exelban/stats` under `docs/stats` as a monitoring implementation reference.

## 5. Dark Mode
- [x] Add `@Environment(\.colorScheme)` to relevant views.
- [x] Replace hardcoded light-only colors with adaptive palette values.
- [ ] Verify readability in light and dark mode.

## 6. Verification
- [x] Build with `xcodebuild -scheme HagimiMonitor -project hagimi-monitor.xcodeproj -destination 'platform=macOS' -derivedDataPath /private/tmp/hagimi-monitorDerivedData build`.
- [x] Launch the debug app and confirm it does not exit.
- [ ] Manually inspect light mode.
- [ ] Manually inspect dark mode.
