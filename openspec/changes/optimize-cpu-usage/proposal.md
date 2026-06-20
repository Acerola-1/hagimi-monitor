# Optimize CPU Usage

## Problem

HagimiMonitor's CPU usage is significantly higher than comparable apps like Stats (5-10%). Analysis identified three main hotspots:

1. **Four independent process sampling timers** trigger every 5 seconds but are staggered, causing ~1.25s average interval between heavy operations (fork+exec `ps`/`nettop`, or full process enumeration with syscalls)

2. **enrich functions run on main thread**, each calling `NSWorkspace.shared.runningApplications` to iterate all running apps, causing main thread congestion

3. **No panel visibility guard** - process sampling continues even when the panel is closed, wasting CPU on data the user can't see

## Goal

Reduce CPU usage to match Stats' 5-10% range by:
- Pausing process sampling when panel is closed
- Moving enrich operations off main thread
- Consolidating process timers to prevent staggered heavy operations

## Success Criteria

- [ ] CPU usage drops significantly when panel is closed
- [ ] Panel opens instantly with cached data, then refreshes
- [ ] No visible degradation in UI responsiveness
- [ ] Process list updates within 1 second of panel opening
