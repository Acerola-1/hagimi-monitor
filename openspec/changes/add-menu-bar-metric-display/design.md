## Context

HagimiMonitor currently renders a single `MenuBarExtra` label as a dynamic halo ring icon. The ring value is driven by `MonitorStore.displayedComputeLoad`, and users can select the ring source from Combined, CPU, GPU, or Memory through `MonitorSettings.ringSource` in General settings.

The desired direction changes two things at once:

1. The halo ring should become simpler: it only represents combined load and no longer needs a user-facing source picker.
2. The menu bar label should become configurable: users can keep the combined load ring or display 1 to 4 selected metrics together as one menu bar button.

The menu bar item must remain a single `MenuBarExtra` so clicking the ring or any metric opens the same monitor panel.

## Goals / Non-Goals

**Goals:**

- Keep the combined load ring as the default menu bar display.
- Remove user-facing ring source selection and treat the ring as combined-load-only.
- Add a metric display mode where users select 1 to 4 menu-bar-friendly metrics.
- Render selected metrics together in the menu bar as one stable label.
- Let users reorder selected menu bar metrics.
- Persist display mode and selected metric order.
- Provide a settings preview and localized Chinese/English text.
- Preserve existing monitor panel behavior and click target.

**Non-Goals:**

- No multi-button status bar implementation.
- No arbitrary custom format strings.
- No metric rotation/animation in the menu bar.
- No user-configurable thresholds or colors in the first version.
- No direct exposure of every panel metric in the menu bar picker.
- No new sensor data sources beyond values already available to the app.

## Decisions

### Decision 1: Model menu bar display separately from panel metrics

Introduce menu bar-specific display settings instead of reusing module metric toggles.

Recommended model shape:

- `MenuBarDisplayMode`: `ring`, `metrics`
- `MenuBarMetricKind`: curated menu bar metric choices such as CPU usage, GPU usage, memory usage, battery level, network download, network upload, CPU temperature, and storage free when available.
- `menuBarMetricKinds: [MenuBarMetricKind]`: ordered selection, capped at 4.

Rationale:

- Panel metrics include long or unsuitable values such as IP address, public IP, uptime, total memory, health, and cycle count.
- Menu bar metrics need short formatting, stable width, and predictable units.
- Keeping a separate model avoids coupling future panel changes to menu bar behavior.

Alternative considered: reuse `MonitorKind.availableMetrics` and `enabledMetrics`. Rejected because many existing metrics are not appropriate for menu bar display and ordering semantics differ.

### Decision 2: Collapse ring source to combined load

Keep the combined load calculation as the only halo ring source. Existing persisted CPU/GPU/Memory ring source values should migrate to combined behavior.

Rationale:

- The ring acts best as a high-level status indicator.
- Users who want a specific value can use metric mode.
- Removing source choice simplifies General settings and avoids overlap between ring and metric mode.

Alternative considered: keep ring source as an advanced option. Rejected because it conflicts with the new product direction and adds unnecessary settings complexity.

### Decision 3: Metric mode supports 1 to 4 selected metrics

Metric mode requires at least one selected metric and allows at most four selected metrics.

Rationale:

- One metric covers the original single-number request.
- Multiple metrics match the desired Stats-like combined status item.
- Four metrics is a practical upper bound for menu bar width and settings complexity.

Alternative considered: allow unlimited metrics. Rejected because the menu bar has limited space and excessive text can be hidden by macOS or crowd other items.

### Decision 4: Render all selected metrics inside one `MenuBarExtra` label

The app should continue using a single `MenuBarExtra`; the label view switches between ring rendering and metric-stack rendering.

Rationale:

- Preserves existing click behavior.
- Avoids multiple status bar buttons.
- Keeps the app conceptually as one monitor item with one expandable panel.

Alternative considered: create one `MenuBarExtra` per selected metric. Rejected because it changes interaction semantics and makes metrics feel like separate apps.

### Decision 5: Use compact, menu-bar-specific formatting

Metric formatting should be short and stable:

- Percent metrics: `42%`
- Temperature: `58°`
- Network throughput: `↓2.4M`, `↑320K`
- Capacity: `128G`

Use monospaced digits and compact labels/icons to reduce width jitter.

Rationale:

- Full labels and full units are too wide for the menu bar.
- Localized full names belong in settings and tooltips, not necessarily in the label.
- Network and capacity values require special short formatting.

Alternative considered: reuse existing sampler value strings exactly. Rejected because values such as `2.4 MB/s`, `128 GB`, or localized labels are too long and inconsistent for a compact menu bar label.

### Decision 6: Settings UI uses preview plus ordered selection

General settings should replace the existing halo ring source picker with a menu bar display section:

- Display mode: combined load ring or metrics.
- Ring mode: no source picker.
- Metrics mode: selectable curated metrics with selected count, maximum count enforcement, ordering controls, and preview.

Rationale:

- Users need immediate feedback on menu bar width.
- Reordering is necessary because left-to-right metric order matters.
- A single section makes the relationship between ring and metrics clear.

Alternative considered: put menu bar metrics under each module settings page. Rejected because users need to configure the menu bar as one combined item, not module by module.

## Risks / Trade-offs

- Menu bar width can become too large → Cap selected metrics at 4, use compact formatting, show a preview, and avoid full localized labels by default.
- Numeric width can jitter as values change → Use monospaced digits and compact fixed-ish formatting for percentages and rates.
- Some metrics can be unavailable on a device → Show `--` for unavailable values and disable unsupported options in settings when availability can be determined.
- Network rates can change rapidly → Do not make network metrics the default; keep updates tied to existing sampling cadence.
- Existing users with non-combined ring source preferences may notice behavior change → Migrate all legacy ring source values to combined behavior and preserve the default ring display mode.
- CPU temperature is build/data-source dependent → Include it only when the app can provide the value; otherwise hide or disable it with explanatory text.

## Migration Plan

- Keep existing users in ring mode by default.
- Treat any existing `settings.ringSource` value as combined after migration; the UI no longer exposes CPU/GPU/Memory ring source choices.
- Initialize metric mode selection with a safe default such as CPU usage when no metric selection exists.
- Persist the new display mode and metric order under new UserDefaults keys.
- Retain compatibility for reading old settings during migration, but do not write legacy ring source choices going forward.

## Open Questions

- Should metric mode show short text labels like `CPU`/`MEM`, icons, or value-only by default?
- Should CPU temperature be included in the first implementation if only available in `DISPLAY_CONTROL` builds?
- Should selected metrics support drag-and-drop ordering immediately, or are up/down controls enough for the first version?
