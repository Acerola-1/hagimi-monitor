## ADDED Requirements

### Requirement: Optimized glass effect clipping
The system SHALL remove redundant `clipShape` from the macOS 15 `CompatibleGlassEffect` implementation, keeping only the inner clipping on `VisualEffectView`.

#### Scenario: Single clip shape on macOS 15
- **WHEN** `CompatibleGlassEffect` is rendered on macOS 15
- **THEN** the `VisualEffectView` SHALL be clipped to `RoundedRectangle`
- **AND** the outer content SHALL NOT have an additional `clipShape` modifier

### Requirement: Appropriate visual effect material
The system SHALL use an appropriate `NSVisualEffectView.Material` for the macOS 15 glass effect that provides visual consistency with the panel design.

#### Scenario: Material selection
- **WHEN** `CompatibleGlassEffect` is rendered on macOS 15
- **THEN** the `VisualEffectView` SHALL use the `.sidebar` material with `.behindWindow` blending
