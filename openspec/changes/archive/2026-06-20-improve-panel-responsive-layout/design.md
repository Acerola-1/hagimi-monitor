## Context

The monitor panel is a compact macOS menu bar surface that combines live metric rows, expandable detail sections, action buttons, and optional direct-build display controls. Recent changes started moving the main panel from a fixed width and fixed point fonts toward flexible width and semantic text styles, but the approach is not yet consistent across all panel content.

The main constraints are:

- The panel must stay compact enough for a menu bar popover while still handling long metric values.
- Metric values, display names, IP addresses, localized strings, and storage volume names can exceed the available width.
- Some fixed dimensions are intentional because icons, sparklines, meters, and compact controls need stable geometry.
- The direct-build display controls are compiled from a separate folder but render inside the same panel surface.

## Goals / Non-Goals

**Goals:**

- Establish a consistent responsive layout model for the monitor panel.
- Replace adaptable text that still uses fixed point sizes with semantic SwiftUI text styles.
- Keep intentional fixed geometry for non-text visual controls.
- Make truncation and scaling behavior explicit for long values.
- Bring direct-build display controls in line with the main panel typography and spacing rules.
- Add verification tasks that exercise collapsed and expanded panel states.

**Non-Goals:**

- Redesign the panel visual language or module ordering.
- Add user-configurable panel width settings.
- Change sampler data models, metric names, or localization keys except where layout verification requires test fixtures.
- Rework menu bar halo behavior, settings window layout, or release packaging.

## Decisions

1. Use panel-level min, ideal, and max width constants.

   The panel should declare a bounded flexible width rather than a single fixed width. This preserves compact behavior on narrow content while allowing long detail content to use more space up to a deliberate maximum.

   Alternative considered: compute width dynamically from screen size. That adds complexity and can make a menu bar popover feel unstable between refreshes; fixed bounds are simpler and predictable.

2. Use semantic text styles for adaptable panel text.

   Panel labels, values, captions, buttons, display-control labels, and badges should use shared helpers built on `Font.TextStyle` instead of repeated `.system(size:)` calls. This aligns with system typography and makes future accessibility or localization adjustments centralized.

   Alternative considered: keep exact point sizes for visual precision. That preserves current appearance but keeps the root problem: text cannot adapt cleanly across display and accessibility settings.

3. Preserve fixed dimensions only for intentional control geometry.

   Fixed icon widths, sparkline sizes, progress meter heights, compact badge padding, and slider geometry are acceptable because they stabilize row scanning and prevent live updates from shifting layout. Text containers and detail sections should not use fixed width unless the width is part of a compact control contract.

   Alternative considered: remove all fixed dimensions. That would make the UI less predictable and can cause charts, icons, and controls to resize based on unrelated text.

4. Prefer explicit truncation for non-critical long text and readable single-column layouts for long-value detail groups.

   Long names and values should use middle truncation where the beginning and suffix matter, such as IP addresses, display names, and volume names. Expanded detail groups with long values should switch from cramped two-column grids to single-column layout when the content type needs it.

   Alternative considered: rely on `minimumScaleFactor` everywhere. That can make text too small to read and does not communicate which content is allowed to lose detail.

5. Align direct-build display controls with the same panel primitives.

   `DisplayControlsSection` should use the same semantic typography, row geometry, and truncation principles as metric rows. This avoids the main app and direct build drifting into different layout behavior inside the same panel.

   Alternative considered: leave display controls unchanged because they are direct-only. That would leave a visible inconsistent section when direct controls are enabled.

## Risks / Trade-offs

- [Risk] Semantic text styles can slightly change current visual density. -> Mitigation: use small styles such as `caption2`, `footnote`, and `callout` intentionally, then verify compact panel states visually.
- [Risk] Wider maximum panel width can feel too large for a menu bar popover. -> Mitigation: keep a conservative maximum and only allow content to expand within explicit bounds.
- [Risk] Truncating metric values can hide diagnostic detail. -> Mitigation: preserve copy-on-click behavior and add help text where long labels or values are intentionally truncated.
- [Risk] Direct-only display controls may be harder to test on machines without compatible external displays. -> Mitigation: isolate layout changes to SwiftUI view code and verify with mocked or fallback display states where possible.
