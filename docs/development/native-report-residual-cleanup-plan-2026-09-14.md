# 原生报表迁移残留审计与实施记录

日期：2026-09-14
范围：原 HTML/WKWebView 报表迁移为 AppKit + SwiftUI 原生窗口后的代码、注释、资源、定时任务、打印与导出链路。
本文件记录审计结论、实施状态和验证证据；清理代码位于产品源码与当前 active OpenSpec。

## 1. 结论

日常报表窗口已经由 `ReportWindowPresenter.open(recorder:anchor:)` 创建 `NSWindow + NSHostingView<NativeReportView>`；打开、范围切换和硬件右栏不读取 HTML 模板，也不创建 `WKWebView`。独立 HTML 只由 `StandaloneHTMLReportExporter` 在用户主动导出或打印时生成。

本轮 C01–C13 已完成代码清理：失效 HTML 实时组和相关 CSS/JS 已删除；原生实时源已按窗口可见性、当前模块和快照变化门控；打印已收敛到幂等 `TransientReportPrintSession`；导出直接写目标 URL；固定报表缓存和存储分类已移除。C14 原生打印评估后保留瞬时 WebKit，原因见下表；C15 原型保留并已标注历史性质；C16 三种语言产品页和报表截图已更新。C17–C19 按边界保留。C06 的双渠道构建与 Direct 全量测试已于本轮完成，active OpenSpec 已同步勾选。

运行时只做了一次只读观察：当时 Direct 与 App Store 两个调试主进程 RSS 约为 324 MiB 和 204 MiB。系统 WebKit XPC 进程均显示为 `ppid=1`，普通 `ps` 无法可靠判断归属；因此这些数值只能作为后续复测起点，不能证明内存由报表或 WebKit 单独造成。

## 2. 清理计划表

| ID | 优先级 | 分类 | 位置 | 实施状态与证据 | 结果/遗留 | 估算 |
|---|---|---|---|---|---|---|---|
| C01 | P0 | 失效逻辑 | `HagimiMonitor/Resources/HardwareSection.js` | ✅ 已完成。移除网页硬件实时组、宿主推送入口和实时定位属性；保留静态硬件规格。`grep` 未发现失效入口标识。 | 独立 HTML 不再渲染无法更新的实时空组。 | 0.5 天 |
| C02 | P0 | 失效样式 | `HagimiMonitor/Resources/HardwareSection.css` | ✅ 已完成。移除仅服务失效标记的变量、选择器和脉冲动画；`node --check HardwareSection.js` 通过。 | 静态硬件卡片样式保留，实时标记样式消失。 | 0.25 天 |
| C03 | P0 | 旧兼容入口 | `HagimiMonitor/ReportWindowPresenter.swift` | ✅ 已完成。删除无调用的 URL 重载及兼容旧入口注释；原生入口保留。 | 调用链只接收 recorder 与可选原生 anchor。 | 0.1 天 |
| C04 | P0 | 旧网页导航语义 | `HagimiMonitor/Statistics/StandaloneHTMLReportExporter.swift` | ✅ 已完成。删除 `StatisticsReportAnchor` 的网页标题属性，并将注释改为原生模块定位。 | 模块 anchor 只表达原生导航 case。 | 0.1 天 |
| C05 | P0 | 注释与命名 | `HagimiMonitor/Hardware/ReportLiveReadings.swift` | ✅ 已完成。类型更名为 `ReportLiveReadings`；注释说明原生右栏契约；有效取值规则和测试保留。 | 未再描述网页推送；本地化短键仍由原生右栏使用。 | 0.25 天 |
| C06 | P0 | 规格与任务状态 | active OpenSpec 的 design/spec/tasks | ✅ 已完成。`design.md`、两份 active spec 与 `tasks.md` 已反映原生窗口、按需导出、打印 session cleanup；C.6 已在双渠道构建与 Direct 全量测试通过后勾选。 | helper 进程退出时间仍不作为对象释放的唯一判断。 | 0.2 天 |
| C07 | P1 | 后台唤醒 | `NativeReportViewModel.swift`、`ReportWindowPresenter.swift` | ✅ 已实现。窗口代理统一门控可见、最小化、遮挡和 App hide/unhide，并在恢复时立即刷新；切 Space 依赖 occlusion state。 | 自动化单测覆盖不可见/恢复；真实多 Space 仍需双渠道实机观察。 | 0.5 天 |
| C08 | P1 | 无效 SwiftUI 发布 | `NativeReportViewModel.swift` | ✅ 已实现并有单测。只在字典变化时发布，timer 设置 tolerance。 | 静止读数不触发重复发布。 | 0.25 天 |
| C09 | P1 | 采集范围 | `NativeReportViewModel.swift`、`ReportHardwareRailView.swift` | ✅ 已实现并有单测。source 只请求当前硬件模块；无实时栏模块停 timer，切换时清空旧值并立即取一帧。 | 六个硬件模块保持实时栏；风扇/蓝牙不伪造实时组。 | 0.5 天 |
| C10 | P1 | WebKit 生命周期 | `ReportWindowPresenter.swift` | ✅ 已实现。`TransientReportPrintSession` 统一成功、取消、导航/脚本失败、重复请求和父窗口关闭出口；cleanup 停止加载、断 delegate、清关联对象、释放引用并删除唯一临时文件。 | 单测已覆盖幂等 cleanup 和临时文件删除；真实打印面板路径需实机验证。 | 1 天 |
| C11 | P1 | 导出文件生命周期 | `StandaloneHTMLReportExporter.swift`、`ReportWindowPresenter.swift` | ✅ 已完成。导出直接写用户目标 URL；打印使用唯一临时 URL，生成在后台执行，导出安全作用域先于后台写入开启。 | Application Support 不再承担完整报表缓存。 | 0.5 天 |
| C12 | P1 | 旧存储模型 | `StatisticsRecorder.swift`、`StorageSettingsView.swift`、`Localizable.xcstrings` | ✅ 已完成。删除固定报表占用、清理入口、存储环分项/确认框和专属文案；总量 fixture 已调整，xcstrings JSON 校验通过。 | 存储页只统计真实持久数据；明细导出能力不受影响。 | 0.5 天 |
| C13 | P2 | HTML 生成峰值 | `StandaloneHTMLReportExporter.swift` | ✅ 已完成结构优化。类型/文件更名；资源按段注入到单一可变字符串；静态符号 CSS 与 app 图标缓存；调用链保持后台生成。 | 尚无 Instruments 新基线，不能把峰值下降量写成实测结论。 | 1 天 |
| C14 | P2 | 打印架构 | `ReportWindowPresenter.swift`、HTML 打印资源 | ⏸ 未实施，保留瞬时 WebKit。当前 HTML 已有分页保护、图表浅色打印样式和浏览器/NSPrintOperation 复用；原生 NSView/PDF renderer 尚未达到全模块长表分页与图表质量的可验证等价物。 | 继续执行 C10 的确定性应用侧 cleanup；不把系统 helper 延迟退出误报为泄漏。 | 2–4 天 |
| C15 | P2 | 历史原型 | `prototypes/report-live-hardware/` | ✅ 保留并已处理。README 顶部标明历史原型、非生产验证；原生实时源和导出链路不依赖它。 | 原型可供布局讨论，新成员不会把它当生产契约。 | 0.25 天 |
| C16 | P2 | 产品文档 | `docs/zh/index.html`、`docs/en/index.html`、`docs/ja/index.html`、`docs/images/stats-report.png` | ✅ 已完成。三种语言改称原生数据报表，只在导出说明保留独立 HTML；截图替换为当前原生概览。 | 产品页与日常产品入口一致。 | 0.5 天 |
| C17 | 保留 | 独立功能 | `HagimiMonitor/Views/Report/ReportDataExporter.swift` | ✅ 保留。明细表 CSV/HTML/Markdown 导出器不参与完整报表窗口实时链路。 | 明细表导出继续可用。 | — |
| C18 | 保留 | 核心统计 | `StatisticsRecorder.record`、数据库分钟/小时/日聚合和进程统计 | ✅ 保留。历史统计数据库和正常采样未因清理 HTML 而删除。 | 原生历史报表仍使用真实统计数据。 | — |
| C19 | 保留 | 原生资源 | `ReportLiveReadings.swift` 与 `ReportLiveReadingsTests.swift` | ✅ 保留。百分号、占位模块、网络速率、本地化状态规则继续由原生右栏消费。 | 仅做命名和注释迁移，没有删有效取值逻辑。 | — |

## 3. 建议实施顺序

| 阶段 | 内容 | 原因 | 预计工作量 |
|---|---|---|---|
| 第一阶段：确定性删残留 | C01–C06 | 均有清晰的无调用或失效证据；先消除错误语义和 OpenSpec 假完成状态 | 1 天内 |
| 第二阶段：压低后台活动 | C07–C09 | 直接针对用户关心的窗口不可见时后台唤醒和无效发布 | 1 天内 |
| 第三阶段：收紧按需 WebKit | C10–C12 | 打印仍会启动 WebKit，必须让每条退出路径可证明释放，并取消固定缓存文件 | 1.5–2 天 |
| 第四阶段：降低峰值与完全去 WebKit | C13–C16 | 属于结构优化和产品收尾，可独立验证；原生打印替换风险最高 | 3–5 天 |

第一、二阶段完成后就应做一次内存复测。不要等第四阶段全部完成才看结果，否则无法判断是哪项改动解决了后台占用。

## 4. 验证矩阵

### 4.1 静态检查

- 全仓应不存在：`liveTimer`、`pushLiveReadings`、`startLiveUpdates`、`ReportScriptMessageHandler`、`ReportNavigationDelegate`、`hagimiPrint`、`__HAGIMI_HARDWARE_LIVE__`、`HW_LIVE_ROWS`。
- 日常入口调用链应保持：`StatisticsReportFlow.open` → `ReportWindowPresenter.open(recorder:)` → `NSHostingView`。
- `WKWebView` 只允许出现在独立打印 session；完成 C14 后应为零。
- HTML 资源只允许由独立 HTML 导出和当前打印实现调用，不能从窗口打开、范围切换或 1 秒实时刷新路径进入。
- 检查两套 scheme，避免 Direct-only 能力或沙盒路径产生不同残留。

本轮静态检查结果：在产品源码、Direct-only、三种现行产品页、active OpenSpec 和实时硬件原型中搜索旧入口标识，未发现匹配；测试文件仅保留对这些标识的负向断言。`WKWebView`/`WebKit` 仅保留在 `HagimiMonitor/ReportWindowPresenter.swift` 的瞬时打印 session 及其 active spec 说明；`node --check HagimiMonitor/Resources/HardwareSection.js` 通过，`jq empty HagimiMonitor/Localizable.xcstrings` 通过。

### 4.2 生命周期场景

按以下顺序分别在 `HagimiMonitor` 与 `HagimiMonitorDirect` 验证：

1. 冷启动后不打开报表，记录主进程 RSS、WebKit helper 数量和 60 秒稳定值。
2. 打开原生报表，等待数据完成加载，记录峰值与 60 秒稳定值。
3. 将窗口完全遮挡、最小化、切换 Space、隐藏应用，各观察 30 秒；确认实时 source 不再触发更新。
4. 关闭报表，分别在 0、10、30、60 秒记录主进程 RSS；确认 `NativeReportViewModel`、图表数据、图标缓存和 timer 已释放。
5. 连续打开/关闭 10 次，稳定值不应阶梯式增长。
6. 导出一次 HTML，确认只产生用户选择的文件，主线程操作流畅，结束后内存回落。
7. 打印正常完成、取消、快速重复点击、加载失败、打印中关闭报表；每次确认 print session 归零且临时文件删除。

建议用 Instruments 的 Allocations、Leaks、SwiftUI 和 Time Profiler 记录证据；活动监视器只作为总量观察。WebKit helper 由系统 XPC 管理，不能单凭 helper 暂未退出判定应用泄漏，应同时确认应用内不再持有 `WKWebView`、delegate、navigation 或打印 session。

### 4.3 构建与测试

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-appstore build

xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-direct build

xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-direct test
```

需要新增或调整的最小测试：

- `ReportLiveHardwareSource`：不可见时不发布、恢复时立即更新、相同快照不重复发布、切换到无实时栏模块时暂停。
- 打印 session：`finish()` 幂等，成功/失败/取消/父窗口关闭均执行相同 cleanup，临时文件删除。
- `StatisticsReportBuilder`/新 exporter：可写指定 URL，不创建固定 Application Support 报表文件。
- 存储模型：移除 `reportBytes` 后总量和环图分项计算正确。
- 独立 HTML 导出快照：无空的“实时”组，静态硬件信息、图表、日期筛选和应用图标仍存在。

本轮实际执行：`./scripts/build-native-report.sh` 使用 `/Applications/Xcode-beta.app`（Xcode 27.0，SDK 27.0）完成 `HagimiMonitor` 与 `HagimiMonitorDirect` 构建，日志见 `tmp/native-report-build-2026-09-14.log`；Direct 全量测试通过（414 项通过、0 项失败），日志见 `tmp/native-report-tests-2026-09-14.log`，其中新增 `ReportLiveHardwareSourceTests`、`TransientReportPrintSessionTests` 与 `StandaloneHTMLReportExporterTests` 均通过。默认命令行 Xcode 26.6/SDK 26.5 不能解析 `.pickerStyle(.tabs)`，因此用项目约定的 Xcode 27 脚本作为本轮双渠道构建证据。

## 5. 不应误删的边界

- 不删除历史统计数据库和 `StatisticsRecorder` 的正常采样。原生报表仍依赖这些数据。
- 不删除 `ReportDataExporter`。它是原始明细表的轻量导出能力，与旧完整网页窗口无关。
- 不删除 `stats.r.hwLive*`、`hwLiveGroup` 等本地化键，除非逐一确认原生 `ReportHardwareRailView` 已不再使用。当前原生右栏仍在使用这些键。
- 不因为 WebKit helper 由系统延迟退出就强杀系统进程。清理目标是应用持有关系、定时工作和临时文件。
- 不整块删除 `ReportTemplate.html`、ECharts、Flatpickr 和 SF Symbol Base64 管线，除非产品明确取消独立 HTML 导出，或已有等价导出实现。它们当前不参与日常原生窗口，但仍服务用户主动导出。
- `openspec/changes/archive/` 是历史决策记录，不做机械重写；只修当前 active change 的任务状态和现行产品文档。

## 6. 验收门槛

本轮清理可以在以下条件全部满足后关闭：

- 打开原生报表不执行 HTML 模板读取、JSON/Base64 组装或创建 `WKWebView`。
- 报表不可见或关闭后没有 1 秒实时 timer 工作；重复开关窗口不存在持续增长。
- 独立 HTML 导出不再展示无法更新的“实时”空状态。
- 打印链路的所有出口都经过可验证的统一 cleanup；打印临时文件不进入长期存储统计。
- App Store 与 Direct 两个构建通过，Direct 测试通过，手动生命周期矩阵有记录。
- OpenSpec 当前任务勾选、代码实现与验证证据一致。

## 7. 追加原生报表 UI（2026-09-14）

- `ReportDataAggregator.coverageRatio` 以 `coverSeconds(for:)` 累计所选行的有效采样秒数，除以有效范围时长后封顶到 `0...1`；空行、零覆盖和无效范围返回 nil。`ReportActiveRangeModel.coverageRatio` 与洞察共用该 helper，概览以 `xx.x%` 展示并保留破折号语义。
- `ReportOverviewView` 将评分摘要前置到告警之后，使用 `ReportCardView` 的紧凑横向表面，依次展示评分、数据完整度和评分依据。秒数口径明确列出内存 60%/热压力 40% 与公式；历史 CPU/GPU 维度显示“历史评分口径”并在帮助文本中保留全部实际维度。
- `ReportCustomRangePicker` 替代顶部两个 compact 日期字段；打开时从当前范围同步草稿，使用起止端点切换与一个 graphical `DatePicker`，应用按 `[start, nextDay(end))` 提交，结束日期不晚于今天，取消不提交。
- 本追加改动已通过 Xcode 27 双渠道构建、Direct 报表相关测试和 Direct 全量测试（日志：`tmp/native-report-direct-full-test-2026-09-14.log`）。尚未在真实 1100×640 / 1380×880 窗口完成中英文及亮暗外观目测，需在最终验收时检查评分带在最小宽度下的英文换行、端点日历操作和 VoiceOver 朗读顺序。
