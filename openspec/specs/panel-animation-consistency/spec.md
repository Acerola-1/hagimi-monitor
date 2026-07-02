## ADDED Requirements

### Requirement: Version-aware detail disclosure transition
The system SHALL share a single `detailDisclosure` transition across all expandable sections in the panel (`MetricGlassRow`, `NetworkGlassRow`, `BatteryGlassRow`, and `DisplayControlsSection`), and SHALL adapt that transition by OS version because `MenuBarExtra(.window)` on macOS 15 does not reconcile a SwiftUI transition with the host window resize.

#### Scenario: macOS 26+ uses geometric transition
- **WHEN** any expandable row is expanded or collapsed on macOS 26+
- **THEN** the transition SHALL be `.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)), removal: .opacity)`

#### Scenario: macOS 15 uses identity transition
- **WHEN** any expandable row is expanded or collapsed on macOS 15
- **THEN** the transition SHALL be `.identity` so no leftover removal frame is rendered against an already-resized window

### Requirement: Version-aware expansion animation
The system SHALL drive expansion state changes through a shared helper that animates with `.easeInOut(duration: 0.25)` on macOS 26+ and mutates state without geometric interpolation on macOS 15, avoiding per-frame window resize jitter from `MenuBarExtra(.window)`.

#### Scenario: macOS 26+ animates expansion
- **WHEN** a row is toggled on macOS 26+
- **THEN** the row height change SHALL interpolate with `.easeInOut(duration: 0.25)`

#### Scenario: macOS 15 expands without geometric interpolation
- **WHEN** a row is toggled on macOS 15
- **THEN** the window SHALL resize to its final size in one step, with the top edge anchored only in the resting state

### Requirement: Progress meter smooth transition
The system SHALL animate the progress bar width change in `ProgressMeter` when the value changes.

#### Scenario: Progress bar animates value change
- **WHEN** the `value` parameter of `ProgressMeter` changes
- **THEN** the width transition SHALL animate with `.easeInOut(duration: 0.3)`
