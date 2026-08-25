## 1. P0 — 安全无争议修复(本次落地)

- [ ] 1.1 F1:修正 `MonitorModels.swift` `refreshProcesses` 的「并行执行」注释为「串行执行」,并注明串行是磁盘/网络全局快照字典(`previousDiskSnapshot` / `previousNetworkSnapshot`)无锁安全的前提
- [ ] 1.2 F4:`NetworkSampler.swift` `sample` 计算 upload/download 速率时对计数器下降(回绕/主接口切换)做归零保护,消除瞬时假峰
- [ ] 1.3 F3:`SMC.swift` `parseValue` 的 `flt ` 分支改用 `loadUnaligned(fromByteOffset:as:)`,消除 `[UInt8]` 上读 `Float` 的对齐未定义行为
- [ ] 1.4 F8:`MonitorPanelView.swift` `parseExternalVolumes` 改用文件级 `static let` 共享 `JSONDecoder`
- [ ] 1.5 F9:`MonitorPanelView.swift` `InlineDiskProcessList` / `InlineNetworkProcessList` 访问级别改为 `private`,与同文件其余视图一致
- [ ] 1.6 `HagimiMonitor` scheme 编译通过
- [ ] 1.7 `HagimiMonitorDirect` scheme 编译通过
- [ ] 1.8 提交 P0 commit(仅纳入 P0 涉及文件,不含在途的 `MenuBarStatusLabel.swift`)

## 2. P1 — 有收益、需验证(后续)

- [ ] 2.1 F7:`MenuBarStatusLabel.swift` 定宽测量结果按 `(kind, fontSize, style)` 静态缓存,消除每周期重建 `NSFont` + 文本测量的热点(先与在途的菜单栏单元对齐改动协调后再动)
- [ ] 2.2 F5:全局检索确认 `SamplingError.ioKitError` 无引用后移除该 case;若仍需保留则补充产出路径
- [ ] 2.3 编译通过 + 菜单栏「指标模式」渲染回归(宽度稳定、无截断)

## 3. P2 — 结构性重构(后续,分独立提交)

- [ ] 3.1 F2:为 `MonitorStore` 添加 `@MainActor`,核对所有调用点与后台派发边界(采样队列/进程采样队列/Combine sink 的 receive(on:))
- [ ] 3.2 F6:重构 `QuickPanelPresentation` 所有权,使菜单栏面板路径不再于 `MonitorPanelView.init` 内 `@ObservedObject(wrappedValue:)` 新建实例
- [ ] 3.3 编译通过 + 菜单栏面板/钉住面板展开收起、快捷键、失焦收起回归

## 4. 收尾

- [ ] 4.1 更新本 tasks 勾选状态,确认 P1/P2 的落地范围与用户对齐
- [ ] 4.2 变更完成后 `openspec archive harden-code-quality`
