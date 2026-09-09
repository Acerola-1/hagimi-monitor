## MODIFIED Requirements

### Requirement: Self-hosted menu bar panel window
The system SHALL present the monitor panel through a self-owned panel window instead of SwiftUI's `MenuBarExtra(.window)`. The panel SHALL keep a real window frame that matches its visible content boundary so native event routing, outside-click dismissal, screen clamping, and system window shadow remain intact.

#### Scenario: Panel opens from status item
- **WHEN** the user left-clicks the menu bar status item and the panel is hidden
- **THEN** the panel SHALL open below the status item at the current settled content size
- **AND** the app SHALL resume panel-visible process sampling

#### Scenario: Panel toggles closed on second click
- **WHEN** the user left-clicks the status item while the panel is visible
- **THEN** the controller SHALL dismiss the panel

#### Scenario: App remains an accessory
- **WHEN** the app launches with the self-hosted panel
- **THEN** the app SHALL remain an `LSUIElement` accessory with no Dock icon
- **AND** no `WindowGroup` window SHALL be shown automatically at launch

### Requirement: Top-anchored smooth resize
The panel SHALL keep its top edge anchored to the menu bar and grow only downward. During expansion, its real window height and all affected content geometry SHALL use the same time sample, while hosted detail content remains at a fixed natural size and does not participate in per-frame SwiftUI layout.

#### Scenario: Expanding a row grows the panel downward
- **WHEN** a row expands while the panel is below the menu bar
- **THEN** the real panel frame SHALL grow downward while its top edge remains fixed
- **AND** the visible content boundary SHALL follow the real panel boundary throughout the transition

#### Scenario: No flicker on resize
- **WHEN** the panel resizes for an expand or collapse
- **THEN** the panel background and the top "SYSTEM · LIVE" header SHALL NOT flash or appear to reload
- **AND** the native system window shadow SHALL remain present without switching to an app-drawn substitute

#### Scenario: Expansion avoids recursive content layout
- **WHEN** a row is expanded or collapsed
- **THEN** the hosted detail content SHALL retain its natural layout throughout the motion
- **AND** animated geometry SHALL NOT be propagated through the complete SwiftUI panel tree on every frame

#### Scenario: Content reports size instantly
- **WHEN** a row's stable natural size or expansion target changes
- **THEN** the content SHALL report the new target without starting a separate geometric SwiftUI animation
- **AND** the unified panel motion coordinator SHALL own all interpolation from the current presentation state

## ADDED Requirements

### Requirement: 可见边界与窗口交互边界一致
菜单栏面板 SHALL NOT use a persistent transparent window extension outside its visible outline. Its physical event region SHALL follow the visible panel so transparent areas do not capture clicks intended for outside dismissal or other applications.

#### Scenario: 点击可见面板外部
- **WHEN** 用户在展开、收起或静止状态点击可见面板轮廓之外
- **THEN** 该点击 SHALL 被视为面板外部交互
- **AND** 面板 SHALL 按现有点外关闭行为退出

#### Scenario: 面板收起后交互区域缩小
- **WHEN** 面板完成收起并释放了下方区域
- **THEN** 已释放区域 SHALL 不继续作为透明面板窗口拦截鼠标事件

### Requirement: 真实窗口与内容共同退化
系统 SHALL 在显示帧更新缺失时保持真实窗口与内容几何处于同一份最近完成的状态，并在下一次更新时共同跳转到基于绝对时间计算的新状态。

#### Scenario: 主线程错过一次动画回调
- **WHEN** 系统负载导致一次预期的动画回调未执行
- **THEN** 窗口与内容 SHALL 保持最近一次共同应用的几何状态
- **AND** 下一次回调 SHALL 不通过补跑中间帧制造额外延迟
