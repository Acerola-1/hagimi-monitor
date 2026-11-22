# Tasks

## 1. 光学绘制与增强对比度适配

- [x] 1.1 在 `HagimiMonitorApp.swift` 扩展 `NSAppearance.isDark` 与 `isHighContrast` 以识别四组系统高对比度外观，并在 `MenuBarStatusSummaryTests` 中验证全部变体判定。
- [x] 1.2 在 `MenuBarComputeRingIcon.swift` 统一底轨与活跃弧同心半径（`13.0pt`）、改为仅绘制剩余未覆盖轨道段、调整圆帽补偿进度映射（`0.06...0.89`）及稳态线宽/实色核心点、适配增强对比度并纳入缓存键；在 `MenuBarComputeRingIconCacheTests` 补齐高对比度缓存键值与 100% 满载顶部缺口像素断言。

## 2. 告警红点与 Game HUD 徽章区分及共存

- [x] 2.1 更新 `MenuBarHUDBadge.swift` 将 HUD 徽章移至右下角并改为 45° 旋转紫色菱形（含反差描边），解除 `MenuBarBadgePresentation` 对同时显示告警与 HUD 的互斥限制；同步更新 `MenuBarComputeRingIcon.swift` 与 `FluidPanelController.swift` 的双徽章独立叠加绘制。
- [x] 2.2 更新 `SamplingGateStateTests.MenuBarBadgePresentationTests` 与 `MenuBarComputeRingIconCacheTests`，验证两枚徽章可同时缓存与绘制且在画布右上/右下各自留有非透明像素，互不覆盖。

## 3. 主状态项悬停摘要、无障碍值、位置记忆与快捷右键菜单

- [x] 3.1 新建 `MenuBarStatusSummary.swift` 封装本地化的悬停 Tooltip 多行摘要与 VoiceOver `accessibilityValue` 格式化逻辑，并新建 `MenuBarStatusSummaryTests.swift` 验证三档状态、内存压力、边界裁剪与告警/HUD 状态组合文案。
- [x] 3.2 在 `FluidPanelController.swift` 为主系统监控状态项接入 `autosaveName = "SystemMonitor"`、`NSViewToolTipOwner` 惰性 Tooltip（随长度变化重注册区域）、增强对比度系统通知订阅、`accessibilityValue` 去重同步，以及右键菜单中的显示模式一键切换与 Direct 渠道 Game HUD 开关。

## 4. 设置页负载环说明、图例与本地化

- [x] 4.1 在 `MenuBarStatusLabel.swift` 为 `MenuBarLoadRingPreview` 补充 `increaseContrast` 参数；在 `GeneralSettingsView.swift` 接入 `@Environment(\.colorScheme)` 与 `@Environment(\.colorSchemeContrast)` 驱动预览，并在负载环模式下展示综合负载说明、三档真实渲染图例及渠道受控的角标图例。
- [x] 4.2 在 `HagimiMonitor/Localizable.xcstrings` 激活 `menu-bar-display.ring-description`、补齐英文刷新率前缀 `"REF"` 及所有新增文案的中英双语翻译与一致格式占位符，确保 `LocalizationFormatAgreementTests` 通过。
- [x] 4.3 在 `MenuBarDisplayModels.swift`、`MenuBarMetricWidthEngine.swift` 与 `MenuBarStatusLabel.swift` 统一升级图标、文字、紧凑三类指标布局的字重/透明度层次、`Hz` 单位拆分、唯一 SF Symbol 与列间距，并新增 `MenuBarMetricLayoutTests.swift` 验证。

## 5. 双渠道联调验证与实机启动对比

- [x] 5.1 使用 `xcodebuild` 分别构建 `HagimiMonitor`（App Store）与 `HagimiMonitorDirect`（Direct）两个渠道并运行 `HagimiMonitorDirect` 全量测试，确认零编译错误与全部测试通过。
- [x] 5.2 重启并打开新构建的 `HagimiMonitor.app` 与 `HagimiMonitorDirect.app`，确认两渠道菜单栏负载环、悬停 Tooltip、右键菜单与设置页图例可正常运行供用户直观对比；检查 `openspec status --change "polish-menu-bar-load-ring"` 与 `openspec validate "polish-menu-bar-load-ring"`。

## Workflow follow-up

- 待用户实机对比确认视觉与交互细节对齐后，再按需执行 `openspec archive polish-menu-bar-load-ring` 并将变更提交至仓库。
