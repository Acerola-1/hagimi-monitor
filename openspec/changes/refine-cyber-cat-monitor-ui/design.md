# Design: Refine Cyber Cat Monitor UI

## Layout
The popover keeps the same two-column concept, but the left column becomes a centered "cat card":

- Speech bubble above the cat, horizontally aligned to the cat body.
- Cat centered in its column, not drifting left or right.
- Cat name/status below the cat, with consistent spacing.
- Right metric list vertically aligned with the cat column and kept compact.

## Menu Bar Icon
The menu bar icon should be optimized for small-size recognition:

- Avoid tiny facial details that blur at 18-22 pt.
- Use a stronger silhouette: ears, head, face, and one state accent.
- Prefer high contrast in both light and dark mode.
- Keep animation out of the menu bar label for stability.

## Metric Formatting
Primary labels use a strict format:

```text
CPU: 80%
GPU: 68%
内存: 62%
存储: 71%
网络: 活动中
电量: 83%
```

Rules:

- No `使用中` suffix.
- Memory primary label is usage, not pressure.
- Secondary labels use one font size and weight across all rows.
- CPU and GPU can show sparklines.
- Memory, storage, network, and battery do not show sparklines.

## Metric Content
CPU:
- Primary: usage percentage.
- Secondary: system/user/idle or equivalent.
- Sparkline: yes.

GPU:
- Primary: usage percentage.
- Secondary: renderer/render utilization, tiler translated as `分块`, memory if available.
- Do not show temperature if unavailable or unstable.
- Sparkline: yes.

Memory:
- Primary: usage percentage.
- Secondary: pressure as a percentage/value, swap memory.
- Remove App and compressed memory fields.
- Do not show pressure as `正常`; show numeric data.

Storage:
- Primary: used percentage.
- Secondary: used/free/total.
- Sparkline: no.

Network:
- Primary: network activity or combined rate.
- Secondary: upload/download only.
- Sparkline: no.

Battery:
- Primary: battery percentage.
- Secondary: state, remaining time, health/cycles/power if space allows.
- Sparkline: no.

## Appearance
The UI must use semantic colors or environment-aware colors. Glass tint, text opacity, separators, and row backgrounds must adapt to `colorScheme`.

Light mode direction:
- White frosted glass.
- Soft warm cat tint.
- Dark text with restrained opacity.

Dark mode direction:
- Charcoal/translucent glass.
- Softer luminous accents.
- Light text with adequate contrast.

