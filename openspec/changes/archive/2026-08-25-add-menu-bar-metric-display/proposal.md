## Why

The menu bar currently centers on a single load ring, which is compact but does not let users read the exact system values they care about at a glance. Users want a Stats-like combined menu bar item where several selected metrics can be shown together while still behaving as one menu bar button.

The existing load ring source selector is also more complex than needed: the ring should only represent the combined load, so users only need to choose whether the ring is shown rather than which source drives it.

## What Changes

- Add a menu bar metric display mode that lets users select 1 to 4 menu-bar-friendly metrics and show them together as one `MenuBarExtra` label.
- Keep the current load ring as a combined-load indicator only.
- Replace the load ring source setting with simpler menu bar display controls: show combined load ring or show selected metrics.
- Provide a settings UI for selecting menu bar metrics, ordering selected metrics, enforcing the maximum count, and previewing the resulting menu bar label.
- Persist the new menu bar display mode and selected metric order in settings.
- Migrate existing load ring source preferences to the new simplified behavior without exposing legacy source choices.
- Localize all new user-facing settings text in Chinese and English.

## Capabilities

### New Capabilities
- `menu-bar-metric-display`: Allows users to configure the menu bar item to show selected metric values, including multi-select, ordering, maximum count, formatting, preview, persistence, and unavailable-value behavior.

### Modified Capabilities
- `halo-ring-source`: Simplifies the halo ring to a combined-load-only indicator and removes the user-facing source selection requirement.
- `menu-bar`: Extends the menu bar item label from ring-only rendering to configurable ring or metric rendering while preserving one-button behavior.

## Impact

- Affected code areas:
  - `MonitorSettings` persistence and migration for menu bar display settings.
  - `MonitorStore` menu bar display value derivation.
  - `MenuBarComputeRingIcon` usage and any new menu bar label view.
  - `HagimiMonitorApp` `MenuBarExtra` label construction.
  - `GeneralSettingsView` or related settings views for menu bar display configuration.
  - `Localizable.xcstrings` for new settings labels and descriptions.
  - Settings/unit tests for defaults, persistence, migration, selection limits, and ordering.
- No external dependencies are expected.
- No change to the menu bar click target: selected metrics must remain part of a single menu bar item that opens the existing monitor panel.
