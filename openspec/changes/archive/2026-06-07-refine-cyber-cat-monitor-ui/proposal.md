# Proposal: Refine Cyber Cat Monitor UI

## Summary
Polish the cyber hardware cat experience so it feels intentional, readable, and native. This change focuses on layout alignment, menu bar icon clarity, metric text normalization, data correctness, typography consistency, and automatic dark mode support.

## Problems
- The left cat is not visually centered and the speech bubble placement feels awkward.
- The menu bar cat icon is not sharp or recognizable enough at status-bar size.
- The right-side metric list mixes labels, suffixes, curves, and small text inconsistently.
- Some displayed metrics are misleading or not useful: GPU temperature is often unavailable, memory "pressure" is actually usage, and memory details show low-value fields.
- The UI currently assumes a light glass surface and does not properly adapt to dark mode.

## Goals
- Center the cat and position the speech bubble so the left column reads as one coherent companion unit.
- Replace or redraw the menu bar cat icon so it remains clear at 18-22 pt.
- Normalize primary metric labels to `Name: Value`, for example `CPU: 80%`.
- Remove all primary `使用中` suffixes.
- Show curves only for CPU and GPU.
- Keep secondary metric typography consistent across rows.
- Replace unavailable or weak metrics with useful ones.
- Support automatic light/dark appearance without a manual setting.

## Non-Goals
- No LLM integration in this change.
- No long-term history database work in this change.
- No redesign of the monitoring sampler architecture beyond required metric substitutions.
- No new settings screen unless necessary for implementation.

## Impact
- `MonitorPanelView.swift` will need layout and row rendering changes.
- `MenuBarCatIcon.swift` will need a clearer status-bar drawing strategy.
- `SystemMonitorSampler.swift` will need display-oriented metric changes, especially memory and GPU.
- `KittyCatView.swift` may need minor alignment affordances, but the cat character should remain the same.

