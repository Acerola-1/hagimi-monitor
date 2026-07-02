## ADDED Requirements

### Requirement: Container background has a fallback on macOS 15
The system SHALL provide a fallback for `.containerBackground(.clear, for: .window)` on macOS 15, ensuring the panel window background remains transparent.

#### Scenario: macOS 26 uses containerBackground
- **WHEN** the app runs on macOS 26+
- **THEN** `.containerBackground(.clear, for: .window)` is applied to the panel view

#### Scenario: macOS 15 uses transparent background fallback
- **WHEN** the app runs on macOS 15
- **THEN** the panel window uses a transparent background via `NSWindow` `isOpaque = false` and `backgroundColor = .clear`

### Requirement: Container background fallback is transparent to callers
The fallback SHALL be implemented as a view modifier so that existing call sites do not need to add `#available` checks inline.

#### Scenario: Caller uses a single modifier
- **WHEN** a view applies `.compatibleContainerBackground(.clear, for: .window)`
- **THEN** the system automatically chooses `.containerBackground` on macOS 26+ or the fallback on macOS 15
