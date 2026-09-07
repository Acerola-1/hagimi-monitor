## Context

See `proposal.md` for the motivation. The current panel is one `NSHostingView` whose SwiftUI root contains the header, a `ScrollView`, a vertical module stack, expandable details, the display section, and footer actions. An expansion changes a SwiftUI `.frame(height:)`; the resulting animation repeatedly traverses `AttributeGraph` and the stack layout while a separate `CADisplayLink` spring calls `NSWindow.setFrame`.

The repository's existing A/B logs show that removing the window spring changes animation-window main-thread time much less than removing content geometry animation. The redesign therefore keeps real window resizing and attacks the dominant recursive layout cost. It must also preserve the current self-owned `NSPanel`, native system shadow, real mouse event region, live `NSVisualEffectView` materials, two distribution channels, screen-height cap, transient menu-bar behavior, and the movable/pinnable panel behavior.

AppKit exposes no public transaction that formally commits `NSWindow` geometry and the window's Core Animation presentation tree as one indivisible WindowServer operation. The design guarantees that the application computes and applies one internally consistent geometry sample per display-link callback, then verifies presentation behavior empirically. It does not claim that an arbitrary overloaded macOS system will produce every VSync or that private WindowServer commit ordering can be proven by the application.

## Goals / Non-Goals

**Goals:**

- Remove expansion progress from SwiftUI layout proposals, state publication, and implicit geometry animation.
- Keep each detail subtree at a stable natural size while revealing it from top to bottom without scale distortion.
- Use one absolute-time motion state for the real window frame, card clipping, sibling displacement, footer position, and automatic scroll reveal.
- Construct the 6pt row gap and 10pt bottom gap in one geometry solver rather than reconciling independently predicted heights.
- Preserve position and velocity when an animation is reversed or redirected.
- Preserve live material, native system window shadow, native event routing, localization, accessibility, and both distribution builds.
- Make missed callbacks advance all affected geometry together rather than allowing an independently running content animation to get ahead of the window.

**Non-Goals:**

- Guarantee that WindowServer or the GPU produces a new frame for every refresh under arbitrary system load.
- Replace native material or native window shadow with app-drawn approximations.
- Use a persistent transparent window envelope, private CGS/SLS APIs, bitmap snapshots, or rasterized animation surrogates.
- Change panel colors, spacing tokens, card content, metric selection, sampler behavior, or distribution capability boundaries.
- Move unrelated value animations such as progress-meter updates into the accordion coordinator.

## Decisions

### 1. Keep the real window boundary and native system behavior

The menu-bar and pinnable panels continue to use their real `NSPanel` frame as the visible boundary. Every animation sample updates that frame while preserving the current top edge. `hasShadow` remains enabled and no replacement shadow layer is introduced.

This avoids a transparent click-catching region, keeps point-out dismissal and other applications' hit regions correct, and preserves the system-rendered shadow. A fixed maximum window envelope was considered and rejected because transparency does not provide public per-pixel event pass-through, an oversized material surface increases compositor work, and the native shadow cannot be relied on to follow an internal presentation mask.

The two panel controllers retain their host-specific positioning rules:

- The menu-bar panel derives its top anchor and horizontal clamp from the status item and current screen.
- The pinnable panel preserves its current top edge while resizing and continues to persist its settled origin.

Both delegate expansion geometry to the same coordinator.

### 2. Replace the animated SwiftUI stack with a lightweight AppKit composition container

The panel content is split into stable hosting islands owned by a flipped `PanelCompositorView`:

```text
NSPanel (real animated frame, native shadow and event region)
└── root live material view
    └── PanelCompositorView
        ├── HeaderHost
        ├── CardHost[cpu]
        │   ├── fixed full-height live material/content
        │   └── top-anchored reveal clip
        ├── CardHost[gpu]
        ├── ...
        ├── DisplayHost
        ├── body viewport / document canvas when capped
        └── FooterHost
```

Each module card has one stable identity and one `NSHostingView` laid out at the card's full natural height. Its SwiftUI subtree renders the collapsed header and complete detail content but receives no animated height or phase. The AppKit wrapper owns the current visible height and clips descendants at the lower edge with the existing continuous 14pt corner geometry. Sibling movement changes only wrapper frames or backing-layer position; it does not resize the hosted content.

The header and footer are separate stable hosts. Card-to-card positioning is manual and token-driven; no `NSStackView` or inter-card Auto Layout constraint graph participates in an animation tick. Auto Layout may still be used inside a stable island where its proposed size does not change during the accordion motion.

One hosting island per logical top-level card is the initial granularity. It isolates data invalidation without multiplying hosting overhead per metric tile. The display section remains one top-level host but registers its nested expandable segments with the panel geometry model so their height contribution can move following top-level siblings.

Alternatives considered:

- A custom SwiftUI `Layout` was rejected because animated height proposals would still invoke `sizeThatFits` and `placeSubviews` every sample.
- A single unchanged root `NSHostingView` with layer offsets was rejected because SwiftUI would still own sibling layout and hit regions, making the presentation geometry difficult to isolate from its model layout.
- One hosting view per metric cell was rejected as excessive lifecycle, memory, focus, and accessibility overhead.

### 3. Measure natural geometry only outside the per-frame path

`PanelGeometrySnapshot` records the stable inputs required to solve a transition:

- panel content width and height cap;
- header and footer heights;
- ordered card identifiers;
- collapsed and full natural heights for every card and nested segment;
- current expansion targets and content-availability flags;
- row, section, inset, and viewport spacing tokens;
- current scroll range and viewport height.

Natural sizes are measured when an island is created or when a geometry-affecting key changes: width, locale, enabled metrics, module order, display topology, channel-specific display controls, accessibility text settings, or content structure. Sampling values that fit existing static contracts repaint the island but do not invalidate the snapshot.

If a genuine natural-height change arrives while a transition is active, the coordinator samples the current position and velocity, creates a new snapshot and target, and retargets from that state. It never overwrites a predicted baseline and never performs an end-of-animation corrective jump.

### 4. Use a single main-thread display-link clock for all accordion geometry

The real window can only be resized through AppKit. Therefore geometry coupled to it must not continue independently as Render Server keyframe animations. A screen display link is active only while motion has not settled. Each callback uses `targetTimestamp` to sample one closed-form spring state and applies the complete geometry vector once on the main actor.

The per-frame path is limited to:

1. Evaluate the analytic motion at the callback's absolute target time.
2. Solve the complete presentation geometry from that motion state.
3. Update the top-anchored real panel frame without implicit AppKit animation.
4. In a disabled-actions Core Animation transaction, update card wrapper positions, reveal bounds, footer position, viewport, and document offset.
5. Stop the display link after applying the exact settled target.

No `@State`, `@Published`, `withAnimation`, animated SwiftUI `.frame`, `GeometryReader` feedback, or `ScrollViewReader.scrollTo` call occurs in this path. Live material composition remains renderer-managed, but accordion geometry does not run ahead of the window on an independent CA timeline.

`setFrame(display: false)` is the initial batching strategy so the container can apply its lightweight geometry before the run-loop commit. The prototype must compare it with the current `display: true` behavior and verify native shadow updates, material continuity, and the absence of re-entrant drawing. The selected form remains behind one small window-application adapter so it can be changed without affecting the motion model.

### 5. Represent motion as an analytic vector and geometry as a constrained solve

For each active expandable segment, the motion state stores phase `q`, velocity `v`, target phase, start time, and shared physical coefficients. The closed-form second-order solution is evaluated at absolute time; it is not numerically integrated from display-frame deltas.

The geometry solver converts the complete phase vector into card heights and positions. In top-down coordinates, it constructs rather than checks the primary invariants:

```text
top[i + 1] = top[i] + visibleHeight[i] + 6
panelHeight = footerTop + footerHeight + 10
```

Equivalently, the output vector `z` remains in the affine constraint set `Az = b`. All geometry consumers read the same solved `z` from the current callback; none independently recomputes panel height or sibling offsets.

Nested expansion is flattened into registered height contributions with ancestry metadata. An outer segment's visible height includes the currently realized inner subtree; an inner segment contributes only while its ancestors are available. A toggle-all action changes all target phases in one transaction and solves one target layout.

The existing response and damping values are the initial visual baseline, not a synchronization mechanism. Synchronization comes from the shared state and solver.

### 6. Add a feasible-boundary rule for spring overshoot

An unconstrained underdamped spring can move a phase below 0 or above 1, which would reveal blank material below full content or reduce a card below its collapsed header. Independently clamping card height, sibling position, and window height would break the shared geometry constraints.

The coordinator therefore constrains canonical phase state before solving geometry:

- A phase that reaches 0 with outward velocity is projected to 0 and its outward velocity component is removed.
- A phase that reaches 1 with outward velocity is projected to 1 and its outward velocity component is removed.
- The full geometry vector is then regenerated from the constrained phase, so all gaps remain exact.

This is modeled as an inelastic contact boundary on a physical spring. User-initiated reversal inherits velocity continuously until a real boundary contact occurs; boundary contact may dissipate outward velocity because bounded valid layout and unconstrained overshoot cannot both be preserved. Tests cover rapid reversals close to both endpoints.

### 7. Make capped scrolling part of the same motion state

When content fits, cards and footer form one flowing vertical sequence. When the screen cap is reached, the architecture uses a fixed header, a clipped card viewport, and a fixed footer whose bottom inset remains 10pt. Card spacing remains defined in document coordinates.

Automatic reveal chooses the last newly expanded row in visual order, aligns enough of its newly revealed content with the viewport bottom, and clamps the result to the valid scroll range. Toggle-all therefore has a deterministic target. The document offset is a component of the same analytic motion state and is applied in the same display-link callback; no independent SwiftUI scroll spring exists.

If direct user scrolling begins during automatic reveal, the coordinator samples the current document offset, cancels only the automatic-scroll target, and rebases the offset to user input while the accordion height motion continues. This prevents two owners from writing the same scroll coordinate.

### 8. Preserve live materials without snapshots or scaling

The existing root popover material and row materials remain live and active. Card content stays at full natural resolution, and only the ancestor reveal bounds changes. No snapshot, `drawingGroup`, layer rasterization, or scale transform is used.

Material selection and blending modes remain unchanged during the first migration. macOS 15 `NSVisualEffectView` and newer-system behavior are validated separately because backdrop cost and clipping behavior can differ. If a future migration uses `NSGlassEffectView`, its moving-edge optical behavior requires a dedicated visual experiment; it is not bundled into this refactor.

### 9. Keep model, hit-testing, focus, and accessibility states coherent

The AppKit wrapper is the authority for the current visible rectangle. Mouse hit testing rejects points outside the current clipped reveal, so fully mounted hidden controls cannot receive clicks. Detail controls become keyboard-focusable and accessibility-visible only when their section is logically expanded; collapse moves focus back to the row header before hiding descendants.

During partial reveal, pointer hit testing is limited to the visible rectangle. Accessibility exposes a stable logical expanded/collapsed state rather than announcing every animation sample. Reduce Motion keeps the same geometry solver and applies the target instantly, preserving all spacing and window behavior.

### 10. Separate semantic state, geometry state, and sampled monitor data

The current `expandedKinds` and display-section expansion choices remain semantic state. A user action creates motion targets but does not publish per-frame phases into SwiftUI. Monitor data continues through the existing main-thread publication model; each hosting island observes only the slice it needs.

Geometry-affecting structure changes are serialized through the coordinator. Value-only samples may update during motion if they do not change natural size. The existing expansion refresh gate can initially remain as a conservative guard and be narrowed after Instruments confirms that isolated islands do not reintroduce layout contention.

### 11. Validate the architecture in native staged prototypes

An HTML prototype cannot validate WindowServer resize, native shadow, event routing, backdrop material, or hosting layout. Implementation therefore begins on an experimental branch with a native three-card harness using the production panel style.

The harness compares these paths under identical scripted toggles:

- current SwiftUI layout animation and window spring;
- fixed-size hosted cards with the new single display-link coordinator;
- window resize alone with static card geometry, to retain a cost floor.

Signposts record callback duration, window application duration, geometry application duration, unexpected hosting/layout passes, missed callback intervals, and settle corrections. Visual capture runs separately from performance measurement because in-process frame capture materially perturbs the main thread.

The full panel migrates only after the harness proves native shadow and material parity, correct point-out behavior, no persistent transparent event area, and a large reduction in expansion-attributable SwiftUI stack layout samples.

## Risks / Trade-offs

- [Risk] Real window geometry and layer commits have no public cross-WindowServer atomicity guarantee. → Use one main-thread sample and one run-loop update, avoid independent CA geometry animations, instrument presentation discrepancies, and treat frame-by-frame visual validation as a release gate.
- [Risk] Per-frame `setFrame` remains a main-thread and WindowServer cost. → Keep the per-frame container path allocation-free and layout-light, measure `display: false` versus `display: true`, and retain the real window because existing A/B data identifies SwiftUI layout as the dominant cost.
- [Risk] Multiple hosting islands increase baseline memory and lifecycle overhead. → Start with one island per top-level card, retain stable identities, unload panel content while hidden as today, and measure visible/hidden footprint before expanding granularity.
- [Risk] Changing an AppKit wrapper frame may accidentally resize or relayout its hosted SwiftUI content. → Give the hosting view a fixed full-size frame, remove animated constraints/autoresizing, keep clipping in the wrapper, and assert natural size remains constant during motion.
- [Risk] Live backdrop materials may repaint more than expected when ancestor clips move. → Preserve existing materials, profile macOS 15 and macOS 26+ independently, avoid rasterization, and reject the path if visual or compositor cost regresses.
- [Risk] Underdamped phase overshoot can create invalid reveal geometry. → Apply the canonical contact-boundary rule before the geometry solve and test rapid reversals near both endpoints.
- [Risk] Nested display sections or device topology changes invalidate cached heights during motion. → Version geometry snapshots and retarget from the current analytic position and velocity whenever a newer snapshot replaces the active one.
- [Risk] Capped scrolling can introduce a second motion owner. → Put automatic document offset in the same coordinator and explicitly rebase it when user scrolling takes ownership.
- [Risk] Hidden mounted controls can receive events or remain in the accessibility tree. → Gate hit testing by the current reveal rectangle and update focus/accessibility at semantic transition boundaries.
- [Risk] Refactoring a 3000-line panel view in one cut would make visual regressions difficult to isolate. → Migrate header/footer and one card first, then each card family and nested display content behind a reversible experimental path.

## Migration Plan

1. Capture baseline Instruments traces, autotest logs, screenshots, native shadow behavior, point-out behavior, and visible/hidden memory for both schemes.
2. Add the geometry and spring components with property-based unit tests before connecting them to any production view.
3. Build a native three-card harness that uses fixed-size hosting islands, live production materials, a real resizing panel, and the single display-link path.
4. Validate the harness on a 60Hz display, ProMotion, Low Power Mode, rapid reversals, and CPU load; abandon or revise the architecture if the real-window/layer update still tears.
5. Introduce the production `PanelCompositorView` behind an internal experimental switch while retaining the current panel implementation as rollback.
6. Migrate header, footer, common metric cards, specialized network/battery rows, display content, and nested display archives in small visual-parity steps.
7. Replace SwiftUI automatic scrolling with the coordinator-owned capped viewport and deterministic reveal target.
8. Switch both panel controllers to the shared coordinator and verify their distinct positioning, pinning, dismissal, and persistence behavior.
9. Run unit, integration, dual-scheme build, performance, memory, accessibility, localization, and frame-by-frame visual checks.
10. Remove the old expandable-height animation, height prediction/calibration, separate window spring, and experimental switch only after the new path passes all gates.

Rollback while the switch exists is an immediate return to the current panel host. After old-path removal, rollback is a source revert of this isolated change; persisted user settings and sampler data require no migration.

## Open Questions

- Whether `setFrame(display: false)` followed by the normal run-loop commit or the current `display: true` produces the best shadow/material behavior must be decided by the native harness microbenchmark.
- Whether the display section should remain one hosting island or split its archive editor into a second stable island can be chosen from measured layout isolation and memory cost without changing the geometry contract.
