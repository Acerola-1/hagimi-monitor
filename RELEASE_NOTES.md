## 更新内容


### 中文

#### 新功能

- **统计报表迁移为 macOS 原生窗口**：彻底淘汰旧版 WebKit 网页视图，重构为轻盈顺滑的原生 SwiftUI 独立报表窗口，消除网页常驻进程与内存开销；支持系统明暗外观、原生侧边栏导航与窗口动态自适应；保留独立离线 HTML 导出能力。
- **键盘锁定小工具重大升级**：支持外接键盘独立识别（「仅锁定内置键盘」可在清洁 MacBook 时保持外接打字，外接拔出安全自愈）、基于 IOHID 物理相对位移特征精确识别设备（彻底排除无线游戏鼠标侧键宏被误判为键盘）、支持 10-60 分钟自动解锁定时兜底、全键位与 F1-F12 亮度音量功能键完整拦截并提供一键授权引导。

#### 优化与体验

- **Swift 6 严格并发适配**：全工程升级至 Swift 6 语言模式并完成严格并发（Strict Concurrency）重构，全面消除多线程数据竞态，提升多核架构稳定性。
- **macOS 27 构建与运行适配**：优化系统诊断并发模型与优雅退出机制，保证最新系统下的无缝运行。
- **报表时间导航与布局优化**：新增原生日期范围选择器（今日、近 7 天、近 30 天与自定义区间），重构总览评分栏与事件块的几何对齐。
- **原生分段选择器**：新增遵循 macOS HIG 规范的实体槽位选择器，消除双层毛玻璃叠加产生的视觉冲突。
- **浮层卡片常驻保护**：补齐存量设置数据迁移，修复小工具关闭时卡片因历史配置缺失而动态消失的问题。

#### 修复

- 修复开启「键盘锁定」并授予辅助功能权限后，点击面板概率性失焦、面板意外消失的问题。
- 修复设置页高负载告警展开按钮悬停时，上方状态卡片产生微小闪烁刷新的问题。
- 修复电源展开区两处连线在不同显示缩放下的对齐与透明度瑕疵。
- 清理后台进程采样中的冗余上下文与废弃代码，进一步压降常驻内存占用。

### English

#### New Features

- **Native Statistics Reports Window**: Completely replaced the legacy WebKit-based report with a responsive, full-native SwiftUI report window, eliminating WebKit runtime memory and CPU overhead while preserving standalone HTML export capability.
- **Enhanced Keyboard Lock Utility**: Added external keyboard distinction (lock only built-in keyboard during cleaning with auto-unlock on disconnect), smart hardware classification (filtering out gaming mouse macro buttons via physical HID relative-axis heuristics), 10–60 min auto-unlock timers, and full suppression of standard and F1–F12 system media keys.

#### Improvements

- **Swift 6 Strict Concurrency**: Migrated the entire codebase to Swift 6 language mode with complete strict concurrency checks enabled, eliminating data races across background samplers.
- **macOS 27 Environment Adaptation**: Refined diagnostic concurrency models and process lifecycle handling for seamless operation on macOS 27.
- **Report Navigation & Overview Polish**: Added a native range selector (Today, Past 7 Days, Past 30 Days, Custom Range) and aligned the health score overview bar with event blocks.
- **Native Segmented Controls**: Introduced HIG-compliant physical tab pickers, avoiding visual conflicts from layered vibrancy effects.
- **Popover Tile Retention**: Fixed an issue where closing a tool in the popover caused its tile to dynamically disappear due to legacy preference migrations.

#### Fixes

- Fixed a probabilistic issue where the panel could lose focus and dismiss unexpectedly on click after enabling Keyboard Lock with Accessibility permission granted.
- Fixed a subtle flicker on the status card when hovering over the high-load alert expansion button in Settings.
- Fixed line alignment and opacity artifacts in the power flow diagram across different display scaling factors.
- Cleaned up obsolete process sampling parameters and dead contexts, reducing baseline idle memory footprint.

