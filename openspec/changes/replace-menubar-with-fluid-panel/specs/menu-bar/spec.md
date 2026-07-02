## MODIFIED Requirements

### Requirement: Stable Menu Bar Rendering
The menu bar label SHALL avoid continuously animated SwiftUI views. The label SHALL be hosted in an `NSHostingView` embedded in `NSStatusItem.button` (managed by `FluidPanelController`) instead of a SwiftUI `MenuBarExtra` label, and this hosting SHALL keep the icon visible and stable without causing the process to terminate.

#### Scenario: App runs in the menu bar
- **WHEN** HagimiMonitor is launched
- **THEN** the menu bar icon remains visible and stable
- **AND** the app does not disappear due to menu bar label rendering

#### Scenario: Status item hosts the label view
- **WHEN** the app launches with the self-hosted panel controller
- **THEN** the status item button SHALL host `MenuBarStatusLabel` via `NSHostingView`
- **AND** the icon SHALL remain visible and stable across sampling updates and appearance changes
