## ADDED Requirements

### Requirement: Quick Tools Entry
The menu bar panel SHALL provide a "Tools" entry in its bottom action row that opens an external popover, visually and semantically separated from the read-only monitoring rows.

#### Scenario: Tools button visible in panel
- **WHEN** the monitor panel is shown
- **THEN** a "Tools" button appears in the bottom action row alongside "Activity Monitor" and "Settings"
- **AND** the button is styled as an action control, not as a monitoring row

#### Scenario: Opening the tools popover
- **WHEN** the user clicks the "Tools" button
- **THEN** an NSPopover opens anchored to the button with `preferredEdge` below (`.maxY`)
- **AND** the popover has a system-drawn arrow pointing at the button
- **AND** the popover is triggered by click, never by hover

#### Scenario: Active-tool badge on entry
- **WHEN** at least one tool is active and the popover is closed
- **THEN** the "Tools" button shows a small badge indicating a tool is running

### Requirement: Adaptive Popover Placement
The tools popover SHALL reposition automatically when the preferred edge lacks space.

#### Scenario: Panel too long, no room below
- **WHEN** the panel extends near the bottom of the screen and the popover cannot fit below
- **THEN** the system repositions the popover to a side (or above) with available space
- **AND** the arrow re-points to the "Tools" button accordingly

### Requirement: Keep Awake Tool
The app SHALL provide a keep-awake tool that prevents idle display sleep, available in both distribution builds.

#### Scenario: Activating keep awake
- **WHEN** the user toggles keep-awake on
- **THEN** an `IOPMAssertion` of type prevent-user-idle-display-sleep is created
- **AND** the tool tile shows an active (lit) state
- **AND** idle display sleep, idle lock, and idle system sleep are prevented while active

#### Scenario: Deactivating keep awake
- **WHEN** the user toggles keep-awake off
- **THEN** the assertion is released and the tile returns to inactive

#### Scenario: State is not persisted
- **WHEN** the app quits or relaunches while keep-awake was active
- **THEN** keep-awake starts inactive on next launch (the assertion is not restored)

#### Scenario: Available in sandbox build
- **WHEN** the App Store (sandbox) build shows the tools popover
- **THEN** the keep-awake tool is present and functional

### Requirement: Keyboard Lock Tool (Direct build only)
The Direct build SHALL provide a keyboard-lock tool that intercepts and swallows all keyboard events while leaving the mouse/trackpad usable.

#### Scenario: Keyboard lock requires accessibility permission
- **WHEN** the user toggles keyboard-lock on without Accessibility permission granted
- **THEN** the app requests Accessibility permission (prompt + open System Settings + poll)
- **AND** the tile shows a "needs Accessibility permission" substate
- **AND** the keyboard is not yet locked

#### Scenario: Locking the keyboard
- **WHEN** the user toggles keyboard-lock on with permission granted
- **THEN** a CGEventTap swallows keyDown/keyUp/flagsChanged events
- **AND** mouse and trackpad remain fully usable (so the user can unlock via the panel)

#### Scenario: Auto-unlock timeout
- **WHEN** the keyboard has been locked for the auto-unlock interval (default 20 minutes)
- **THEN** the keyboard unlocks automatically and the tile returns to inactive

#### Scenario: Tap disabled by system
- **WHEN** the event tap is disabled by timeout or user input
- **THEN** the tap is automatically re-enabled while lock remains active

#### Scenario: Excluded from sandbox build
- **WHEN** the App Store (sandbox) build shows the tools popover
- **THEN** the keyboard-lock tool is absent (code excluded at compile time)

### Requirement: Tools Popover Visual Language
Tools SHALL be presented as light-up toggle tiles distinct from monitoring rows.

#### Scenario: Inactive tile appearance
- **WHEN** a tool is inactive
- **THEN** its tile shows a neutral glass background with a gray icon badge and an off substate

#### Scenario: Active tile appearance
- **WHEN** a tool is active
- **THEN** its tile fills with the tool's accent color (lit), the icon badge is fully saturated, and the substate text uses the accent color

#### Scenario: Liquid Glass on capable systems
- **WHEN** running on macOS 26 or later
- **THEN** the popover uses the system Liquid Glass material
- **AND** on macOS 15 it falls back to the standard popover vibrancy material

### Requirement: Tools Localization
All tool names, states, and permission prompts SHALL be localized in zh-Hans, en, and ja.

#### Scenario: Tool names localized
- **WHEN** the system locale is zh-Hans
- **THEN** the tools show "键盘锁定" and "防休眠"
- **AND** under en they show "Keyboard Lock" and "Keep Awake"
## ADDED Requirements

### Requirement: Quick Tools Entry
The menu bar panel SHALL provide a "Tools" entry in its bottom action row that opens an external popover, visually and semantically separated from the read-only monitoring rows.

#### Scenario: Tools button visible in panel
- **WHEN** the monitor panel is shown
- **THEN** a "Tools" button appears in the bottom action row alongside "Activity Monitor" and "Settings"
- **AND** the button is styled as an action control, not as a monitoring row

#### Scenario: Opening the tools popover
- **WHEN** the user clicks the "Tools" button
- **THEN** an NSPopover opens anchored to the button with `preferredEdge` below (`.maxY`)
- **AND** the popover has a system-drawn arrow pointing at the button
- **AND** the popover is triggered by click, never by hover

#### Scenario: Active-tool badge on entry
- **WHEN** at least one tool is active and the popover is closed
- **THEN** the "Tools" button shows a small badge indicating a tool is running

### Requirement: Adaptive Popover Placement
The tools popover SHALL reposition automatically when the preferred edge lacks space.

#### Scenario: Panel too long, no room below
- **WHEN** the panel extends near the bottom of the screen and the popover cannot fit below
- **THEN** the system repositions the popover to a side (or above) with available space
- **AND** the arrow re-points to the "Tools" button accordingly

### Requirement: Keep Awake Tool
The app SHALL provide a keep-awake tool that prevents idle display sleep, available in both distribution builds.

#### Scenario: Activating keep awake
- **WHEN** the user toggles keep-awake on
- **THEN** an `IOPMAssertion` of type prevent-user-idle-display-sleep is created
- **AND** the tool tile shows an active (lit) state
- **AND** idle display sleep, idle lock, and idle system sleep are prevented while active

#### Scenario: Deactivating keep awake
- **WHEN** the user toggles keep-awake off
- **THEN** the assertion is released and the tile returns to inactive

#### Scenario: State is not persisted
- **WHEN** the app quits or relaunches while keep-awake was active
- **THEN** keep-awake starts inactive on next launch (the assertion is not restored)

#### Scenario: Available in sandbox build
- **WHEN** the App Store (sandbox) build shows the tools popover
- **THEN** the keep-awake tool is present and functional

### Requirement: Keyboard Lock Tool (Direct build only)
The Direct build SHALL provide a keyboard-lock tool that intercepts and swallows all keyboard events while leaving the mouse/trackpad usable.

#### Scenario: Keyboard lock requires accessibility permission
- **WHEN** the user toggles keyboard-lock on without Accessibility permission granted
- **THEN** the app requests Accessibility permission (prompt + open System Settings + poll)
- **AND** the tile shows a "needs Accessibility permission" substate
- **AND** the keyboard is not yet locked

#### Scenario: Locking the keyboard
- **WHEN** the user toggles keyboard-lock on with permission granted
- **THEN** a CGEventTap swallows keyDown/keyUp/flagsChanged events
- **AND** mouse and trackpad remain fully usable (so the user can unlock via the panel)

#### Scenario: Auto-unlock timeout
- **WHEN** the keyboard has been locked for the auto-unlock interval (default 20 minutes)
- **THEN** the keyboard unlocks automatically and the tile returns to inactive

#### Scenario: Tap disabled by system
- **WHEN** the event tap is disabled by timeout or user input
- **THEN** the tap is automatically re-enabled while lock remains active

#### Scenario: Excluded from sandbox build
- **WHEN** the App Store (sandbox) build shows the tools popover
- **THEN** the keyboard-lock tool is absent (code excluded at compile time)

### Requirement: Tools Popover Visual Language
Tools SHALL be presented as light-up toggle tiles distinct from monitoring rows.

#### Scenario: Inactive tile appearance
- **WHEN** a tool is inactive
- **THEN** its tile shows a neutral glass background with a gray icon badge and an off substate

#### Scenario: Active tile appearance
- **WHEN** a tool is active
- **THEN** its tile fills with the tool's accent color (lit), the icon badge is fully saturated, and the substate text uses the accent color

#### Scenario: Liquid Glass on capable systems
- **WHEN** running on macOS 26 or later
- **THEN** the popover uses the system Liquid Glass material
- **AND** on macOS 15 it falls back to the standard popover vibrancy material

### Requirement: Tools Localization
All tool names, states, and permission prompts SHALL be localized in zh-Hans, en, and ja.

#### Scenario: Tool names localized
- **WHEN** the system locale is zh-Hans
- **THEN** the tools show "键盘锁定" and "防休眠"
- **AND** under en they show "Keyboard Lock" and "Keep Awake"
