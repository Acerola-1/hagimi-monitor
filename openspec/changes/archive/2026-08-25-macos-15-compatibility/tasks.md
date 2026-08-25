## 1. 兼容层组件创建

- [x] 1.1 创建 `CompatibleGlassContainer.swift` — 封装 `GlassEffectContainer` / `NSVisualEffectView` 双路径
- [x] 1.2 创建 `CompatibleSymbolEffect.swift` — 封装 `.symbolEffect` / opacity fallback
- [x] 1.3 创建 `CompatibleContainerBackground.swift` — 封装 `.containerBackground` / 透明窗口 fallback

## 2. 面板视图替换

- [x] 2.1 替换 `MonitorPanelView.swift` 中的 `GlassEffectContainer` 为 `CompatibleGlassContainer`
- [x] 2.2 替换 `MonitorPanelView.swift` 中的 `.glassEffectID` 调用
- [x] 2.3 替换 `MonitorPanelView.swift` 中的 `.glassEffect` 调用（MetricGlassRow、NetworkGlassRow、BatteryGlassRow）
- [x] 2.4 替换 `MonitorPanelView.swift` 中的 `.symbolEffect` 调用（header live dot、battery charging）
- [x] 2.5 替换 `MonitorPanelView.swift` 中的 `.containerBackground` 调用

## 3. 设置视图替换

- [x] 3.1 替换 `SettingsLayout.swift` 中的 `GlassEffectContainer` 为 `CompatibleGlassContainer`
- [x] 3.2 替换 `StatisticsView.swift` 中的 `GlassEffectContainer` 为 `CompatibleGlassContainer`
- [x] 3.3 替换 `EventTimelineView.swift` 中的 `.glassEffect` 调用

## 4. 显示控制模块替换

- [x] 4.1 替换 `DisplayControlsSection.swift` 中的 `.glassEffect` 调用

## 5. 项目配置与构建

- [x] 5.1 修改 `project.pbxproj` 中 `MACOSX_DEPLOYMENT_TARGET` 为 15.0
- [x] 5.2 验证 macOS 26 开发机编译通过
- [x] 5.3 打包 Release 版本供 macOS 15 测试机验证

## 6. 测试与回归

- [x] 6.1 macOS 26 上验证 Glass 视觉效果无变化
- [ ] 6.2 macOS 15 测试机上验证应用可正常启动
- [ ] 6.3 macOS 15 上验证面板展开/收起、header 动画正常
- [ ] 6.4 macOS 15 上验证设置窗口正常显示
