## ADDED Requirements

### Requirement: Responsive Panel Width
The monitor panel SHALL use bounded flexible width constraints instead of a single fixed content width.

#### Scenario: Panel renders collapsed content
- **WHEN** the monitor panel renders its default collapsed module list
- **THEN** the panel uses a configured minimum width, ideal width, and maximum width
- **AND** the content does not require a single hard-coded fixed panel width

#### Scenario: Expanded content needs more horizontal space
- **WHEN** an expanded panel section contains longer labels or values
- **THEN** the panel may grow beyond its ideal width up to the configured maximum width
- **AND** content that still exceeds the maximum width is truncated according to its content type

### Requirement: Adaptive Panel Typography
Panel text SHALL use semantic SwiftUI text styles for adaptable labels, values, captions, buttons, and badges.

#### Scenario: Main metric rows render
- **WHEN** CPU, GPU, memory, storage, network, or battery rows render
- **THEN** row labels, values, and captions use shared semantic text style helpers
- **AND** the implementation does not use fixed point-size fonts for adaptable text in those rows

#### Scenario: Display controls render in the direct build
- **WHEN** the direct-build display controls section appears in the panel
- **THEN** display labels, summaries, badges, and slider labels use semantic text styles aligned with the main panel
- **AND** the section does not keep independent fixed point-size fonts for adaptable text

### Requirement: Intentional Fixed Geometry
The panel SHALL keep fixed dimensions only for stable non-text visual geometry and compact controls.

#### Scenario: Visual controls render
- **WHEN** icons, sparklines, progress meters, sliders, or compact badges render
- **THEN** their fixed dimensions are allowed only when they stabilize scanning, alignment, or control interaction
- **AND** text containers do not use fixed width unless they are part of an explicit compact control contract

### Requirement: Long Panel Content Handling
The panel SHALL handle long metric values, localized labels, display names, network identifiers, and storage volume names without overlapping adjacent UI.

#### Scenario: Network details contain long values
- **WHEN** network details include long IP addresses, interface names, upload values, or download values
- **THEN** the expanded details use a layout that preserves readable label/value relationships
- **AND** overflowing values use explicit truncation or scaling behavior without overlapping other controls

#### Scenario: Storage or display names are long
- **WHEN** a storage volume name or display name exceeds available width
- **THEN** the name is truncated in the middle or otherwise preserves the most useful identifying portions
- **AND** adjacent percentage, badge, slider, or status controls remain visible and aligned

#### Scenario: Localized text is longer than the current language baseline
- **WHEN** localized labels or button titles are longer than their Chinese baseline text
- **THEN** the panel keeps readable spacing and avoids text overlap in collapsed and expanded states
