## Context

The monitor panel currently has a neutral blue-gray base with lower-saturation module accents. Before that refinement, the panel used stronger module-colored glass and separators, which gave the app a more distinctive colorful identity. The new setting should expose both visual directions while keeping the code organized for future palettes.

Relevant current state:
- `MonitorSettings` already persists app preferences through `UserDefaults`.
- `SettingsView` already has a General -> Appearance section for light/dark theme preference.
- `MonitorPanelView` currently resolves module tint through `MonitorKind.paletteTint`.
- `MonitorPanelTheme` and `DisplayControlTheme` separately define base text, glass, separator, and track colors.
- `DisplayControlsSection` lives in the Direct target and currently has its own display tint and theme struct.

## Goals / Non-Goals

**Goals:**
- Add a persisted color scheme preference with balanced as the default.
- Provide a vibrant palette that restores colorful module-tinted panel surfaces while following the current compact panel layout and typography rules.
- Move color ownership into palette models so view code asks for semantic tokens instead of branching on specific schemes.
- Use the same palette source for the main monitor rows and Direct display controls.
- Keep severity colors separate from module accents.
- Make it straightforward to add future palettes with minimal view changes.

**Non-Goals:**
- Changing sampling behavior, module visibility behavior, update checking, or display control capabilities.
- Adding custom user-defined colors.
- Changing app-wide light/dark appearance selection; the existing theme setting remains separate.
- Reintroducing the old layout, old typography, or previous text contrast choices.

## Decisions

### Add a palette preference enum to settings

Introduce a `MonitorColorSchemePreference` enum with at least:
- `balanced`: the current default, neutral blue-gray surfaces with quieter module accents.
- `vibrant`: the colorful panel style, using stronger module accents and module-derived row surfaces.

Rationale: the setting belongs beside the existing Appearance section and should persist the selected visual style. Missing stored values should resolve to `balanced`.

Alternative considered: store raw color values in `UserDefaults`. Rejected because the feature is preset-based, and raw persisted colors would complicate migration and validation without enabling a requested workflow.

### Introduce a palette model that owns semantic color tokens

Create a palette abstraction, for example `MonitorPalette`, that can answer:
- base text colors for the current light/dark appearance
- track fill, live dot, and neutral surface tokens
- module accent colors for `MonitorKind`
- display accent color
- severity colors for `MonitorSeverity`
- row glass and separator colors for a module/display section

Rationale: views should consume semantic tokens like `rowGlassTint(for:)` and `moduleTint(for:)`, not know whether the current scheme is balanced or vibrant.

Alternative considered: keep `MonitorKind.paletteTint` and add a switch on the selected setting inside each view. Rejected because it couples domain enums and views to visual schemes, making future palettes harder to add.

### Model surface behavior as part of the palette

The balanced palette uses neutral blue-gray glass and separators. The vibrant palette uses module-derived glass and separators with controlled opacity, preserving the old colorful-panel spirit while keeping the current panel rules.

Rationale: vibrant is not only a different icon color set; the module-colored surface is part of the feature. Treating surface behavior as palette output avoids reverting view structure.

Alternative considered: have vibrant only change module icon/chart colors. Rejected because it would not restore the distinctive colorful panel requested by the user.

### Keep severity semantic and independent

`MonitorSeverity` should not hardcode SwiftUI colors directly. It should expose semantic state, and the palette should provide severity tint values.

Rationale: warning and critical colors represent status, not CPU/GPU/module identity. Keeping them separate prevents normal module accents from looking like alerts.

### Share palette resolution with Direct display controls

`DisplayControlsSection` should receive or construct the same selected palette from `MonitorSettings`. Display controls should use the palette's display accent and surface tokens instead of a private theme with hardcoded colors.

Rationale: otherwise future visual changes can make the display module diverge from the main panel again.

## Risks / Trade-offs

- [Risk] Palette abstraction may feel heavier than two color choices. -> Keep the model small and token-based; avoid adding custom color editing or over-generalized style engines.
- [Risk] Vibrant mode can become too noisy if old surface opacities are restored exactly. -> Use the old color identity but keep current panel spacing, text colors, and controlled opacity.
- [Risk] Existing users could see an unexpected palette if stored values are invalid. -> Default missing or unknown values to balanced.
- [Risk] Main and Direct targets can diverge if display colors remain local. -> Route display tint and display surfaces through the shared palette.
