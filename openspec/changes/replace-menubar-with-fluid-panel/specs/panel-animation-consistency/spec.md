## MODIFIED Requirements

### Requirement: Version-aware detail disclosure transition
The system SHALL share a single `detailDisclosure` transition across all expandable sections in the panel (`MetricGlassRow`, `NetworkGlassRow`, `BatteryGlassRow`, and `DisplayControlsSection`). Because the panel is now hosted in a self-owned `NSPanel` whose height is animated at the window layer (see `fluid-menu-bar-panel`), the transition SHALL be identical on macOS 15 and macOS 26+ and SHALL NOT branch by OS version.

#### Scenario: Unified transition on all supported versions
- **WHEN** any expandable row is expanded or collapsed on macOS 15 or macOS 26+
- **THEN** the content transition SHALL be the same definition on both versions
- **AND** the transition SHALL NOT introduce geometric interpolation that competes with the window-layer height animation

#### Scenario: Height change is smooth without flicker
- **WHEN** a row is expanded or collapsed
- **THEN** the panel height SHALL interpolate smoothly via the window layer
- **AND** no leftover removal frame SHALL be rendered against a mismatched window size

### Requirement: Version-aware expansion animation
The system SHALL drive expansion state changes through a shared helper. Because the window layer now provides the smooth height interpolation with the top edge anchored (see `fluid-menu-bar-panel`), the helper SHALL mutate expansion state without OS-version branching and without per-version geometric animation, on both macOS 15 and macOS 26+.

#### Scenario: Expansion toggles uniformly
- **WHEN** a row is toggled on macOS 15 or macOS 26+
- **THEN** the expansion state SHALL update through the shared helper on both versions
- **AND** the resulting height change SHALL be interpolated by the window layer, not by a per-version SwiftUI geometry animation

#### Scenario: Top edge stays anchored during animation
- **WHEN** the panel grows or shrinks from an expansion toggle
- **THEN** the top edge SHALL remain anchored at the menu bar throughout the animation
