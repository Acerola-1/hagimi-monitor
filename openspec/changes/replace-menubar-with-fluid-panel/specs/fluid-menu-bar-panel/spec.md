## ADDED Requirements

### Requirement: Self-hosted menu bar panel window
The system SHALL present the monitor panel through a self-owned `NSPanel` created and managed by `FluidPanelController`, instead of SwiftUI's `MenuBarExtra(.window)`, because `MenuBarExtra(.window)` on macOS 15 redraws the whole host window on every content-size change and causes the panel to flicker on expansion.

#### Scenario: Panel opens from status item
- **WHEN** the user left-clicks the menu bar status item and the panel is hidden
- **THEN** the controller SHALL size the panel to the SwiftUI content's fitting size and order it front below the status item
- **AND** the app SHALL call `panelDidAppear()` to resume process sampling

#### Scenario: Panel toggles closed on second click
- **WHEN** the user left-clicks the status item while the panel is visible
- **THEN** the controller SHALL dismiss the panel

#### Scenario: App remains an accessory
- **WHEN** the app launches with the self-hosted controller
- **THEN** the app SHALL remain an `LSUIElement` accessory with no Dock icon
- **AND** no `WindowGroup` window SHALL be shown automatically at launch

### Requirement: Top-anchored smooth resize
The panel SHALL keep its top edge anchored to the menu bar and grow only downward, and SHALL animate height changes at the window layer via `setFrame(display:animate:)` so that no SwiftUI view tree rebuild occurs during resize.

#### Scenario: Expanding a row grows the panel downward
- **WHEN** the SwiftUI content reports a taller fitting size while the panel is visible
- **THEN** the controller SHALL compute the new frame with `origin.y -= newHeight` so the top edge stays fixed at the menu bar
- **AND** SHALL apply the new frame with `animate: true`

#### Scenario: No flicker on resize
- **WHEN** the panel resizes for an expand or collapse
- **THEN** the panel background and the top "SYSTEM · LIVE" header SHALL NOT flash or appear to reload

#### Scenario: Content reports size instantly
- **WHEN** a row is expanded or collapsed
- **THEN** the SwiftUI content SHALL report its new size without geometric `withAnimation`, leaving height interpolation to the window layer

### Requirement: Dynamic status item icon hosting
The status item SHALL host the existing `MenuBarStatusLabel` SwiftUI view inside an `NSHostingView` embedded in `NSStatusItem.button`, so both the dynamic halo ring and the variable-width metrics label render correctly.

#### Scenario: Ring mode renders
- **WHEN** the menu bar display mode is the halo ring
- **THEN** the status item SHALL display the dynamic ring reflecting the current compute load

#### Scenario: Metrics mode renders variable width
- **WHEN** the menu bar display mode is metrics text
- **THEN** the status item width SHALL follow the hosting view's intrinsic content size

#### Scenario: Appearance change refreshes icon
- **WHEN** the effective appearance (light/dark) or theme preference changes
- **THEN** the hosted label SHALL refresh so the icon keeps sufficient contrast

### Requirement: Dismissal and system integration
The controller SHALL dismiss the panel on outside interaction and integrate with system menu tracking and multi-display geometry.

#### Scenario: Click outside closes panel
- **WHEN** the panel is visible and the user clicks outside it
- **THEN** the controller SHALL dismiss the panel with a fade-out

#### Scenario: Resign key closes panel
- **WHEN** the panel loses key window status
- **THEN** the controller SHALL dismiss the panel

#### Scenario: Full screen keeps menu bar
- **WHEN** the panel is shown while another app is in full screen
- **THEN** the controller SHALL post begin/end menu-tracking notifications so the menu bar stays visible while the panel is open

#### Scenario: Panel clamps to screen edge
- **WHEN** the panel's computed frame would extend past the screen's right or left visible edge
- **THEN** the controller SHALL shift the frame horizontally to stay within the screen's visible area
