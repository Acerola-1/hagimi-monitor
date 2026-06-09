## Context

The monitor panel currently uses SwiftUI Liquid Glass at multiple levels: the menu-bar window shell, metric rows, display controls in the Direct build, and command buttons. On macOS 26 this produced a restrained frosted look. On macOS 27 Beta 1, SwiftUI glass and `.glass` button rendering are visibly stronger, especially in dark mode: row highlights, hover states, specular edges, and background refraction compete with the metric content.

Apple's macOS 27 release notes explicitly mention a SwiftUI fix for `.glass` and `.glassProminent` buttons outside toolbars not displaying hover state. This likely explains why the bottom command buttons and other glass-like controls become more prominent when running the same app on macOS 27.

The project supports macOS 26+ only and Apple Silicon only, so no pre-26 fallback is required. The App Store and Direct targets must remain separated, and display-control UI must stay Direct-only.

## Goals / Non-Goals

**Goals:**
- Preserve a native macOS 26/27 appearance while keeping dark-mode metrics readable over bright or complex backgrounds.
- Treat the system menu-window glass as the outer shell and avoid stacking multiple full-panel glass surfaces.
- Reduce Liquid Glass usage on dense content rows and command buttons if macOS 27 continues to render them too prominently.
- Keep the current metric layout, ordering, typography hierarchy, and palette semantics.
- Make any macOS 27-specific choices explicit and easy to tune after later betas.

**Non-Goals:**
- No sampler, metric, display-control, entitlement, or sandbox changes.
- No redesign of the menu bar icon.
- No new settings option unless later testing shows users need to choose between native glass and subdued content styling.
- No implementation during this proposal; this is intentionally deferred until macOS 27 behavior stabilizes.

## Decisions

### Use One Outer Glass Shell

The system `MenuBarExtra(.window)` shell should remain the only full-window glass layer. A separate full-size SwiftUI `.glassEffect` or full-panel material background risks producing mismatched corner radii and visible double borders.

Alternative considered: keep the full-panel `.glassEffect` and tune corner radii. This is fragile because the system window's radius, inset, and refraction behavior are platform-controlled and changed between macOS 26 and macOS 27.

### Add a Subdued Reading Surface Inside the Shell

The panel should use an inset reading surface to protect text and charts from background interference. This surface should not touch the outer window corners. It can be a simple color scrim or a low-emphasis material, tuned separately for light and dark appearances.

Alternative considered: remove the reading surface entirely. Testing showed dark-mode readability suffers when bright desktop or window content passes through the system glass.

### Make Dense Rows Less Glass-Heavy

Metric rows should prioritize legibility and unity over individual glass object identity. If macOS 27 keeps the stronger Liquid Glass rendering, rows should use palette-driven translucent fills, subtle borders, and standard hover feedback rather than `.glassEffect` for every row.

Alternative considered: keep glass rows and reduce tint opacity. This may still leave system-controlled specular edges and hover effects that cannot be fully tuned through palette colors.

### Replace `.buttonStyle(.glass)` For Panel Commands If Needed

The bottom Activity Monitor and Settings commands should not become the visual focus of the panel. If `.glass` remains too prominent on macOS 27, replace it with a custom quiet button style using the same reading-surface palette.

Alternative considered: use `.plain` buttons only. Plain buttons can become too weak for repeated actions; a custom background gives predictable affordance without strong glass highlights.

### Prefer Compile-Time/Availability Branches Over User Settings Initially

The first implementation should prefer platform-aware styling through availability checks or isolated style tokens. Add a user setting only if macOS 27's final glass behavior remains polarizing and users need control.

Alternative considered: add a "subdued glass" preference immediately. That adds settings complexity before the beta behavior is stable.

## Risks / Trade-offs

- macOS 27 beta rendering may change again -> defer implementation until later beta or release candidate, and keep the proposal focused on observable behavior rather than Beta 1-specific constants.
- Removing row glass can make the panel feel less native -> keep the system outer shell glass and use subtle row borders/shadows to preserve depth.
- Inset reading surfaces can look like an inner card -> keep the inset small, avoid high-contrast borders, and tune opacity per appearance.
- Direct display controls may diverge from metric rows -> apply the same surface/token strategy to `DisplayControlsSection` when the Direct build is tested.
- Cross-version tuning can become scattered -> centralize visual constants in `MonitorPalette` or `MonitorConstants` rather than hardcoding them inside row views.
