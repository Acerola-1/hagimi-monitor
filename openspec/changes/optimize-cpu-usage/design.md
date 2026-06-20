# Design: CPU Usage Optimization

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Current Architecture                         │
├─────────────────────────────────────────────────────────────────────┤
│  cpuProcTimer ──(5s)──> samplingQueue ──> main thread enrich()      │
│  memoryProcTimer ──(5s)──> memoryProcQueue ──> main thread enrich() │
│  diskProcTimer ──(5s)──> diskProcQueue ──> main thread enrich()     │
│  networkProcTimer ──(5s)──> networkProcQueue ──> main thread enrich()│
│                                                                     │
│  Problem: 4 independent timers, staggered triggers, main thread    │
│           blocked by NSWorkspace.shared.runningApplications         │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        Target Architecture                          │
├─────────────────────────────────────────────────────────────────────┤
│  panelVisible: Bool (new)                                          │
│       │                                                             │
│       ├─ false → procTimer paused, cache preserved                 │
│       │                                                             │
│       └─ true → unifiedProcTimer ──(5s)──> background queue        │
│                      │                                              │
│                      ├─ sampleCPUProcesses()                        │
│                      ├─ sampleMemoryProcesses()                     │
│                      ├─ sampleDiskProcesses()                       │
│                      └─ sampleNetworkProcesses()                    │
│                              │                                      │
│                              ▼                                      │
│                      enrich all in background                       │
│                      (NSRunningApplication per PID)                 │
│                              │                                      │
│                              ▼                                      │
│                      main thread: update @Published                 │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Changes

### 1. Panel Visibility Detection

SwiftUI's `MenuBarExtra` doesn't provide a direct visibility callback. Options:

**Option A: NSApplication activation state**
- Monitor `NSApplication.didBecomeActiveNotification` / `didResignActiveNotification`
- Limitation: app may be active without panel open

**Option B: Window enumeration**
- Poll `NSApplication.shared.windows` for MenuBarExtra window visibility
- Limitation: requires timer, fragile

**Option C: onAppear/onDisappear on panel content**
- Use SwiftUI lifecycle on MonitorPanelView
- ✅ **Recommended**: Clean, no polling, works with MenuBarExtra

```swift
MonitorPanelView(store: monitorStore)
    .onAppear { store.panelDidAppear() }
    .onDisappear { store.panelDidDisappear() }
```

### 2. Unified Process Timer

Replace 4 independent timers with 1 unified timer:

```swift
// Before: 4 timers, staggered
memoryProcTimer = Timer.publish(every: 5, ...)
cpuProcTimer = Timer.publish(every: 5, ...)
diskProcTimer = Timer.publish(every: 5, ...)
networkProcTimer = Timer.publish(every: 5, ...)

// After: 1 timer, sequential execution
procSampleTimer = Timer.publish(every: 5, ...)
    .sink { _ in
        procSampleQueue.async {
            sampleAllProcesses()  // sequential, not parallel
        }
    }
```

Benefits:
- True 5s interval (not 1.25s average)
- Single queue prevents resource contention
- Easier to pause/resume

### 3. Background Enrich

Replace `NSWorkspace.shared.runningApplications` with per-PID lookup:

```swift
// Before: iterate all apps
@MainActor
func enrichCPU(_ raw: [RawCPUProcess]) -> [TopCPUProcess] {
    let appsByPid = Dictionary(
        NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    // ...
}

// After: per-PID lookup, can run on any thread
func enrichCPU(_ raw: [RawCPUProcess]) -> [TopCPUProcess] {
    return raw.map { proc in
        let app = NSRunningApplication(processIdentifier: pid_t(proc.pid))
        let name = app?.localizedName ?? proc.fallbackName
        let icon = app?.icon ?? defaultProcessIcon
        return TopCPUProcess(pid: proc.pid, name: name, cpuUsage: proc.cpuUsage, icon: icon)
    }
}
```

Note: `NSRunningApplication.icon` is thread-safe for reading. We can enrich on background thread and only update `@Published` on main thread.

### 4. Cache Strategy

When panel closes:
- Keep `topCPUProcesses`, `topMemoryProcesses`, etc. at their last values
- Stop timer

When panel opens:
- Immediately display cached values (already in @Published)
- Trigger one immediate sample
- Restart timer

```swift
func panelDidAppear() {
    isPanelVisible = true
    refreshAllProcesses()  // immediate sample
    startProcTimer()
}

func panelDidDisappear() {
    isPanelVisible = false
    stopProcTimer()
    // cache preserved automatically (topXxxProcesses unchanged)
}
```

## Thread Safety

```
Background Queue                    Main Thread
─────────────────                   ───────────
sampleAllProcesses()                
    │                               
    ├─ sampleCPUProcesses()         
    ├─ sampleMemoryProcesses()      
    ├─ sampleDiskProcesses()        
    └─ sampleNetworkProcesses()     
            │                       
            ▼                       
    enrich all (per-PID lookup)     
            │                       
            ▼                       
    DispatchQueue.main.async {      
        self.topCPUProcesses = ...  
        self.topMemoryProcesses = ...
        self.topDiskProcesses = ... 
        self.topNetworkProcesses = ..
    }                               ───> @Published update
                                        ───> UI refresh
```

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `onAppear`/`onDisappear` may not fire reliably with MenuBarExtra | Test thoroughly; fallback to window polling if needed |
| `NSRunningApplication(processIdentifier:)` returns nil for short-lived processes | Already handled: fallback to `fallbackName` / `defaultProcessIcon` |
| Panel open latency | Cache provides instant display; immediate sample starts on appear |
| Settings changes while panel closed | Settings changes already trigger immediate refresh via Combine subscribers |
