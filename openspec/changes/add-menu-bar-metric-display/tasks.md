## 1. Settings Model and Migration

- [x] 1.1 Add menu bar display mode model with `ring` and `metrics` modes.
- [x] 1.2 Add curated menu bar metric kind model with compact labels, localization keys, default selection, and stable identifiers.
- [x] 1.3 Add persisted settings for menu bar display mode and ordered selected metric kinds.
- [x] 1.4 Enforce metric selection rules in settings: at least one selected metric and at most four selected metrics.
- [x] 1.5 Migrate legacy halo ring source values so all previous CPU/GPU/Memory/Combined values behave as combined ring display.
- [x] 1.6 Remove or deprecate user-facing halo ring source selection paths while preserving compatibility with old stored values.

## 2. Menu Bar Metric Value Derivation

- [x] 2.1 Add logic to derive compact menu bar metric values from current monitor modules.
- [x] 2.2 Implement percentage formatting for CPU, GPU, memory, battery, and storage usage metrics.
- [x] 2.3 Implement compact capacity formatting for storage free space.
- [x] 2.4 Implement compact directional throughput formatting for upload and download metrics.
- [x] 2.5 Handle unavailable metric values with a compact placeholder without hiding the menu bar item.
- [x] 2.6 Keep combined load ring value and load level based only on combined load.

## 3. Menu Bar Label Rendering

- [x] 3.1 Create a menu bar label view that switches between combined load ring rendering and metric rendering.
- [x] 3.2 Render selected metric values in one horizontal label inside the existing single `MenuBarExtra`.
- [x] 3.3 Use compact spacing and monospaced digits to reduce menu bar width jitter.
- [x] 3.4 Ensure metric value updates do not use continuous animations.
- [x] 3.5 Preserve existing click behavior so any rendered metric opens the current monitor panel.

## 4. Settings UI

- [x] 4.1 Replace the General settings halo ring source picker with a menu bar display section.
- [x] 4.2 Add controls for choosing combined load ring display or metric display.
- [x] 4.3 Add a curated metric selection UI with selected count and maximum-count feedback.
- [x] 4.4 Add ordering controls for selected metrics.
- [x] 4.5 Add a live preview of the resulting menu bar label.
- [x] 4.6 Hide or disable unsupported metrics, such as CPU temperature when no value source is available.

## 5. Localization

- [x] 5.1 Add Chinese and English strings for menu bar display mode labels, metric names, selection limit messages, ordering controls, preview labels, and unavailable-state text.
- [x] 5.2 Remove or stop using localized strings that only describe selecting CPU/GPU/Memory as halo ring sources.

## 6. Tests and Verification

- [x] 6.1 Add settings tests for default display mode, default metric selection, persistence, maximum selection count, and non-empty selection enforcement.
- [x] 6.2 Add migration tests for legacy halo ring source values mapping to combined ring behavior.
- [x] 6.3 Add formatting tests for percentage, throughput, capacity, and unavailable metric values.
- [x] 6.4 Build the development scheme with `HagimiMonitorDirect`.
- [ ] 6.5 Manually verify ring mode, metric mode with one metric, metric mode with multiple metrics, ordering, settings preview, and single-button menu bar behavior.
