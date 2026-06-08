## 1. Settings Model

- [x] 1.1 Add a `MonitorColorSchemePreference` enum with Balanced and Vibrant options, user-facing titles, stable raw values, and default Balanced behavior.
- [x] 1.2 Add a published color scheme preference to `MonitorSettings`, load it from `UserDefaults`, persist changes, and treat missing or unknown stored values as Balanced.
- [x] 1.3 Add focused unit coverage for default color scheme loading and persistence behavior.

## 2. Palette Architecture

- [x] 2.1 Introduce a shared palette model that resolves text, track, live dot, module accent, display accent, surface, separator, and severity tokens from the selected color scheme and light/dark appearance.
- [x] 2.2 Move current Balanced colors into the palette model without changing the current default visual result.
- [x] 2.3 Add Vibrant palette tokens using the old colorful panel identity, including stronger module accents and module-derived glass/separator surfaces with controlled opacity.
- [x] 2.4 Remove direct color ownership from `MonitorKind.paletteTint` and `MonitorSeverity.tint` so views resolve colors through the palette.

## 3. UI Integration

- [x] 3.1 Add the color scheme picker to Settings -> General -> Appearance, keeping it independent from the existing light/dark theme picker.
- [x] 3.2 Update `MonitorPanelView`, metric rows, detail rows, sparklines, and progress meters to consume palette tokens instead of hardcoded module/theme colors.
- [x] 3.3 Update Direct display controls to consume the same palette source for display accent, glass tint, separator, badge fill, and text tokens.
- [x] 3.4 Ensure changing the color scheme updates the open monitor panel without requiring app restart.

## 4. Verification

- [x] 4.1 Build the sandbox app target with `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug build`.
- [x] 4.2 Build and launch the Direct target with `./launch.sh` to verify the user-visible development app.
- [x] 4.3 Manually inspect Balanced and Vibrant in light and dark appearance for text readability, colorful panel behavior, display module consistency, and severity color independence.
