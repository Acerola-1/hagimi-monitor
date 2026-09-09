## Purpose

Provides a user-controlled persistence toggle between modern system Liquid Glass and classic frosted material on supported macOS versions, with strict separation between window-level backdrops and card-level materials.

## ADDED Requirements

### Requirement: Liquid Glass 持久化偏好设置
系统 SHALL 在「设置 → 常规 → 外观」中提供 Liquid Glass 开关，并在支持的 macOS 系统（26+）上默认处于关闭状态（使用经典毛玻璃），设置值即时持久化到 UserDefaults。

#### Scenario: 默认关闭状态
- **WHEN** 应用在全新安装或未显式配置 Liquid Glass 开关的系统上首次启动
- **THEN** Liquid Glass 开关处于关闭（false）状态
- **AND** 面板窗口与卡片使用经过验证的经典毛玻璃材质

#### Scenario: 切换开关即时生效与材质分层
- **WHEN** 用户在设置窗口中切换 Liquid Glass 开关
- **THEN** 监控面板窗口底座宿主（Window Backdrop）即时在 `NSGlassEffectView` 与 `.popover + .behindWindow` 之间无缝切换，无需重启应用且不触发面板跳变
- **AND** 内部行卡片（Row Cards）严格保持 `.withinWindow` 毛玻璃，不参与液态玻璃合并，杜绝展开 resize 闪烁
