## Why

当前监控面板只能从菜单栏状态项点击弹出，且失焦即自动关闭（见 `FluidPanelController.windowDidResignKey`），无法长时间停留在桌面上。用户希望像「图片钉图」一样，用全局快捷键随时呼出一个可拖动、可固定在桌面任意位置、始终位于其他窗口之上的常驻监控面板，从而在工作时持续观察系统指标，而不必反复去点菜单栏。

## What Changes

- 新增**全局快捷键**（可在设置中自定义、可清除），按下即切换钉住面板的显示/隐藏。
- 新增**钉住面板窗口**（独立于现有菜单栏面板），复用现有 `MonitorPanelView` 内容，特性包括：
  - **可拖动**：按住面板背景即可拖到桌面任意位置。
  - **始终最前**：浮于普通应用窗口之上（`.floating` 层级），不随失焦或点击外部而关闭。
  - **记住位置**：拖动后的窗口位置持久化，下次呼出与 App 重启后恢复到上次位置。
  - **仅当前桌面显示**：不跟随切换虚拟桌面（Spaces），即不启用 all-spaces 行为。
- 新增**显式入口与关闭方式**：菜单栏面板提供「钉住」按钮；再次按快捷键或点击「取消钉住」按钮隐藏。
- 新增**设置项**：快捷键录制控件，并明确录制必须包含修饰键。
- **修改采样可见性判定**：`MonitorStore.isPanelVisible` 由单一布尔改为引用计数式判定，使菜单栏面板与钉住面板任一可见时采样均保持活跃。
- 所有新增用户可见文案在 `Localizable.xcstrings` 补齐 `zh-Hans` 与 `en`。

## Capabilities

### New Capabilities
- `pinnable-panel`: 全局快捷键呼出/关闭、可拖动、始终最前、位置持久化、仅当前桌面显示的常驻监控面板能力。

### Modified Capabilities
- `monitor-panel`: 面板可见性状态由单一布尔改为「任一面板可见即视为可见」的引用计数判定，供进程采样与显示器 DDC 轮询的启停使用。

## Impact

- **新增代码**：`PinnedPanelController`（新建，参照 `FluidPanelController` 但反转移动/失焦/层级行为）、全局快捷键封装、钉住相关设置 UI。
- **依赖**：新增 SPM 依赖 `KeyboardShortcuts`（Sindre Sorhus），底层用 Carbon `RegisterEventHotKey`，无需辅助功能权限，兼容 App Store 沙盒版。
- **修改**：`MonitorStore`（可见性引用计数）、`AppDelegate`（持有并连接钉住控制器与快捷键）、`MonitorSettings`（窗口位置）、设置视图、`Localizable.xcstrings`。
- **复用**：`MonitorPanelView`、`TransparentWindowBackground`、`CompatibleGlassContainer` 等现有组件直接沿用，macOS 15 / 26 兼容层不变。
