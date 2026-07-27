# 任务清单

## 1. 恢复实现

- [ ] 1.1 `git apply openspec/changes/adopt-liquid-glass/implementation.patch`（冲突则按 design.md 核心决策手工重做）
- [ ] 1.2 `./launch.sh` 构建并启动，确认菜单栏面板与设置窗口渲染正常

## 2. 微调评估（design.md「遗留微调项」逐项过）

- [ ] 2.1 深色/浅色模式下检查面板行 tint 浓度，必要时调整 `MonitorPalette.rowGlassTint(for:)`
- [ ] 2.2 深色模式下评估底部按钮 `.glass` 观感，偏亮则加 `.tint()` 或回退 `.frosted`
- [ ] 2.3 评估行 `.interactive()` 悬停反馈是否与现有交互打架，不合适则降为 `.liquid`
- [ ] 2.4 （可选）验证面板窗口底换 `NSGlassEffectView` 的 resize 动画表现

## 3. 性能与回归验证

- [ ] 3.1 面板展开状态 CPU < 10%（`top -pid $(pgrep HagimiMonitor)`）
- [ ] 3.2 连续快速展开/收起多行，确认无闪烁、窗口补间同步
- [ ] 3.3 macOS 15 测试机回归：视觉与行为与降级前完全一致
- [ ] 3.4 跑单测（`SettingsTests`、`MenuBarComputeRingIconCacheTests` 等）确认无回归

## 4. 规范同步

- [ ] 4.1 修正 `openspec/specs/macos15-glass-compatibility/spec.md`：材质描述改为实际的 `.menu + .withinWindow`
- [ ] 4.2 在该 spec 补充场景边界：面板行 26+ 液态玻璃 / 15 毛玻璃回退、静态区域允许 `.liquid`
- [ ] 4.3 验收通过后归档本变更（archive）
