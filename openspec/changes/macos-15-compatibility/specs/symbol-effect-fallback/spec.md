## ADDED Requirements

### Requirement: Symbol effect has a fallback on macOS 15
The system SHALL provide a fallback for `.symbolEffect` on macOS 15, using an alternative animation that does not require macOS 26+ APIs.

#### Scenario: Pulse animation fallback on macOS 15
- **WHEN** the live dot indicator uses `.symbolEffect(.pulse)` on macOS 26
- **THEN** on macOS 15 it uses `.opacity` animation with a repeating timer to simulate pulsing

#### Scenario: Variable color animation fallback on macOS 15
- **WHEN** the battery charging icon uses `.symbolEffect(.variableColor.iterative)` on macOS 26
- **THEN** on macOS 15 it uses a static icon without animation, or a simple opacity toggle if charging

### Requirement: Symbol effect fallback is transparent to callers
The fallback SHALL be implemented as a view modifier or wrapper so that existing call sites do not need to add `#available` checks inline.

#### Scenario: Caller uses a single modifier
- **WHEN** a view applies `.compatibleSymbolEffect(.pulse)`
- **THEN** the system automatically chooses `.symbolEffect(.pulse)` on macOS 26+ or the fallback on macOS 15
