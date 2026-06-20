# Tasks: CPU Usage Optimization

## Task 1: Add Panel Visibility Tracking

**Files**: `MonitorModels.swift`, `HagimiMonitorApp.swift`

- [ ] Add `@Published var isPanelVisible: Bool = false` to MonitorStore
- [ ] Add `panelDidAppear()` and `panelDidDisappear()` methods
- [ ] Add `.onAppear` / `.onDisappear` to MonitorPanelView in HagimiMonitorApp

## Task 2: Consolidate Process Timers

**Files**: `MonitorModels.swift`

- [ ] Remove 4 separate timer properties: `memoryProcTimer`, `cpuProcTimer`, `diskProcTimer`, `networkProcTimer`
- [ ] Add single `procSampleTimer: AnyCancellable?`
- [ ] Create `refreshAllProcesses()` that calls all 4 sample functions sequentially
- [ ] Create `startProcTimer()` and `stopProcTimer()` methods
- [ ] Wire timer to `isPanelVisible` changes

## Task 3: Move Enrich to Background Thread

**Files**: `TopCPUProcess.swift`, `TopMemoryProcess.swift`, `TopDiskProcess.swift`, `TopNetworkProcess.swift`, `MonitorModels.swift`

- [ ] Remove `@MainActor` from `enrichCPU()`
- [ ] Replace `NSWorkspace.shared.runningApplications` with `NSRunningApplication(processIdentifier:)` per-PID lookup
- [ ] Remove main thread dispatch in `refreshTopCPUProcesses()` (enrich now runs on background queue)
- [ ] Keep `DispatchQueue.main.async` only for final `@Published` update
- [ ] Repeat for `enrichMemory()`, `enrichDisk()`, `enrichNetwork()`

## Task 4: Implement Panel-Aware Sampling

**Files**: `MonitorModels.swift`

- [ ] In `panelDidAppear()`: set `isPanelVisible = true`, call `refreshAllProcesses()`, start timer
- [ ] In `panelDidDisappear()`: set `isPanelVisible = false`, stop timer (cache preserved)
- [ ] Remove settings change triggers for proc timers (they'll be handled by panel visibility)
- [ ] Keep settings change triggers but check `isPanelVisible` before refreshing

## Task 5: Testing

- [ ] Verify panel opens with cached data instantly
- [ ] Verify process list refreshes within 1s of panel opening
- [ ] Verify CPU usage drops when panel is closed
- [ ] Verify settings changes work correctly with new timer logic
- [ ] Verify no memory leaks from timer management

## Implementation Order

```
Task 1 (visibility tracking)
    │
    ▼
Task 2 (consolidate timers)
    │
    ▼
Task 3 (background enrich)  ← can be done in parallel with Task 2
    │
    ▼
Task 4 (panel-aware sampling)
    │
    ▼
Task 5 (testing)
```

## Estimated Impact

| Metric | Before | After |
|--------|--------|-------|
| Panel closed CPU | ~5-15% | ~1-2% (main sampling only) |
| Panel open CPU | ~5-15% | ~5-10% (single timer, background enrich) |
| Main thread blocks | ~4x per 5s | ~0x (enrich moved to background) |
| Process list latency | 0s (always running) | 0s (cached) + <1s (refresh) |
