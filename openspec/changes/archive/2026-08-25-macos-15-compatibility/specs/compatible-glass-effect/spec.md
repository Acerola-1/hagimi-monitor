## ADDED Requirements

### Requirement: Compatible glass container supports macOS 15 fallback
The compatible glass container SHALL render a glassmorphism-style background on both macOS 26+ and macOS 15, using native `GlassEffectContainer` on macOS 26+ and `NSVisualEffectView` on macOS 15.

#### Scenario: macOS 26 uses native GlassEffectContainer
- **WHEN** the app runs on macOS 26+
- **THEN** the panel uses `GlassEffectContainer` with `.glassEffect` and `.glassEffectID`

#### Scenario: macOS 15 uses NSVisualEffectView fallback
- **WHEN** the app runs on macOS 15
- **THEN** the panel uses a custom `NSVisualEffectView`-backed container that approximates the glass effect

### Requirement: Compatible glass container accepts the same content layout
The compatible glass container SHALL accept the same child content and spacing parameters as the original `GlassEffectContainer`, so existing view code requires minimal changes.

#### Scenario: Content layout is preserved across versions
- **WHEN** a view wraps its content in the compatible glass container
- **THEN** the content layout and spacing are identical on both macOS 15 and macOS 26

### Requirement: Compatible glass container supports corner radius and tint
The compatible glass container SHALL support corner radius and tint color parameters, mapping them to the appropriate macOS API.

#### Scenario: Corner radius and tint are applied on macOS 26
- **WHEN** corner radius and tint are specified
- **THEN** `.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius, style: .continuous))` is used

#### Scenario: Corner radius and tint are applied on macOS 15
- **WHEN** corner radius and tint are specified
- **THEN** the `NSVisualEffectView` applies the tint color and masks corners using a layer mask
