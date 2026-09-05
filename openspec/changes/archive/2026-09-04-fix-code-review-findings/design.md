# 设计：审查发现修复的实施方式

## Context

本次变更源于一份 53 条已验证发现的全分支审查报告（见 proposal.md 的 Why，不复述）。代码库现状的关键约束：

- **双 target 单 scheme**：`HagimiMonitor`（App Store/沙盒）与 `HagimiMonitorDirect` 两个 app target 的 `PRODUCT_NAME` 都硬编码为 `HagimiMonitor`（project.pbxproj:651/701），全项目仅一个共享 scheme；单测 `HagimiMonitorTests` 的 `TestTargetID` 指向 Direct target。这导致测试构建图中出现两个同名产物而失败——修测试问题必须先动构建接线。
- **仓库已有三处成熟的子进程看门狗实现**（BluetoothBatterySampler / StorageSMARTProbe / ChargeLimitProbe：后台线程读输出 + 信号量超时 + `terminate()` + 放弃本次结果），但 nettop/ps 两处周期采样没有套用。
- **展开动画竞态已在提交历史中修过 3 次**（365cd451 / 7989586e / c05ff50f），竞态防护代码在 `FluidPanelController` 与 `PinnedPanelController` 各有一份且已分叉（钉住版缺屏幕底部钳制）。
- **统计汇总当前每分钟全窗口重扫**（`StatisticsDatabase.maintain` 的 `rollUp` 把 `resumeFrom` 设为源表最早行），与产品宣称的"常年零 IO"矛盾。
- 伽马调光的文件注释（GammaDimmingController.swift:21-23）描述的参数布局（min/max/gamma 槽位）与 CoreGraphics 实际要求不符，当前调用以 `factor` 占据 gamma 槽而被拒绝（错误 1007）。

## Goals / Non-Goals

**Goals:**
- 批次 A/B 的每一项有独立、可演示或可单测的验收手段；批次顺序保证"修任何东西之前先有绿色测试 + CI"。
- 修复复用仓库既有模式（看门狗、串行队列收口），不引入新依赖、新框架。
- 结构性偿还（批次 C）每一项独立提交、可单独回滚。

**Non-Goals:**
- 不做 `MonitorStore` / `FluidPanelController` 的全面拆分、WiFiProbe 独立队列、`MetricGlassRow` Equatable 重构（见 proposal"明确不做"）。
- 不重写统计存储层、不改数据文件位置或格式（B4 只改维护策略）。
- 不调整 App Store 与 Direct 的功能边界。

## Decisions

### D1 测试构建修复：Direct 产物改名，而非改测试宿主

**选择**：将 `HagimiMonitorDirect` 的 `PRODUCT_NAME` 改为 `HagimiMonitorDirect`，并相应修正 scheme 测试动作的宿主引用；沙盒 target 保留 `HagimiMonitor` 产物名（App Store 出包路径不动）。

**理由**：冲突的根因是"两个 target 产出同名 bundle"。备选方案是保持双同名产物、给测试单独设 DerivedData 路径——被否：只掩盖问题，任何同时构建两 target 的场景（未来的双渠道 CI）仍会撞。沙盒产物名保持 `HagimiMonitor` 使 App Store 归档/上传脚本（`scripts/release.sh` 的沙盒分支）零改动。

**影响核查**：Direct 产物改名后需同步检查 `release.sh` Direct 分支、Sparkle appcast 路径、图标与资源拷贝中所有硬编码 `HagimiMonitor.app` 的位置（release.sh Direct 段是主要风险点，B2 任务中显式包含该核查）。

### D2 看门狗：直接移植既有探针模式，不抽公共工具

**选择**：把 `ChargeLimitProbe` 的"后台读 + 信号量 + 超时终止"模式复制到 `TopNetworkProcess`（nettop）与 `TopCPUProcess`（ps），超时值取 8s（探针类为 4-8s；进程列表输出量更大，取上限）。暂不抽公共 `SubprocessWatchdog` 工具函数。

**理由**：抽公共工具是更"正确"的终态，但 nettop/ps 的调用形态（参数构造、输出解析、失败语义"保留上次结果"）与探针（返回 Optional）差异不小，先复制 2 处落地、把三处探针是否也顺手统一留给后续。备选"给 readDataToEndOfFile 加文件长度上限"被否：不解决挂起语义。

**超时后的语义**：返回 `nil` → 调用方保留上一份列表（现状空结果已有占位处理，不新增状态）。

### D3 深链修复：先挂载观察者再广播，广播补兜底重放

**选择**：`SettingsWindowPresenter` 改为"窗口内容与路由观察者就绪后再消费 `pendingTab`"；同时 `pendingTab` 在广播时不清空，由观察者消费后清除。若采用通知机制则广播携带标签页值（新观察者挂载即可读取），彻底消除时序窗口。

**理由**：根因是"广播发生于任何观察者挂载之前"。只调整挂载顺序能修首次打开，但若未来出现窗口复用路径会再次踩坑；兜底重放使正确性不依赖时序。备选"延迟一帧再广播"被否：把时序竞态换成更隐蔽的时序竞态。

### D4 DDC 重放：抑制门记录最后一次被跳过的写入，窗口结束补发

**选择**：在 `DDCEnvironmentGate`（或其调用层）为每个（显示器, VCP 码）保留最近一次 `.skipped` 的目标值；抑制窗口结束的既有回调里统一补发。

**理由**：备选"写入方自行重试"需要每个滑杆/控制点各自管理重试状态，发散且易漏；门本来就掌握窗口生命周期，由门统一补发是单点职责。多次连续调节只重放最后一次（用户意图以最后一次为准）。

### D5 汇总增量化：封口驱动 + 删除驱动两条增量路径

**选择**：
- **分钟封口**：只重算刚封口小时桶的增量（该小时已封口分钟的变化量并入小时行），小时行变化再上卷日行——单次开销恒定。
- **删除/修正**：维护接口接受"受影响时间桶集合"，只重算这些桶的聚合。

**理由**：备选"把全量重扫降频（每小时一次）"被否：只是常数优化，开销仍随数据年龄线性增长，违背 spec 的有界性要求。增量方案需要汇总记录水位（上次汇总到哪个桶），以一张极小的元数据行持久化，避免依赖"应用从未中断"的假设。

### D6 竞态防护收敛：抽共享协调器，两个控制器持有同一实例

**选择**：把 `applyWindowHeight`/`contentSizeDidChange`/token 校正逻辑抽为面板共享的窗口高度协调器（含屏幕底部钳制——钉住版当前缺失的行为一并补齐），两个控制器替换为调用。清理描述已删除 60Hz 设计的过期注释。

**理由**：这块代码已被逐字复制且分叉，是三次竞态回归的温床；不收敛则 C 批次的任何面板改动都要双写。备选"只修分叉点不抽公共"被否：治标。

### D7 报表修复：模板内最小改动，不动数据侧

**选择**：A7-A9 全部在 `ReportTemplate.html` 内修：结束边界改排他比较（`day < toKey` 语义修正）、日表遍历改用模板内已有的本地午夜归一化写法（`dailyTotals` 处已有正确先例，直接对齐）、覆盖时长两处改走已有的 `coverSeconds()`。

**理由**：数据侧（Swift 落库的 dayKey/cover_s）已被复核确认正确，问题全在模板消费端。

### D8 CI：单 workflow，双构建串行测试

**选择**：新增 `.github/workflows/ci.yml`：push/PR 触发 → `xcodebuild build` 沙盒 target（Release）+ `xcodebuild test`（D1 修复后的测试路径）。macOS runner 上构建时间可观，暂不做矩阵。

**理由**：首要目标是"红测试不再静默发版"。UITests 目前无可跑宿主（见 B2 核查范围），CI 先只覆盖单测，UITest 的死权重留待后续决定（保留或删除）。

## Risks / Trade-offs

- **[Direct 产物改名波及发布脚本]** → B2 显式包含对 `release.sh` Direct 分支、appcast、资源路径的全量核查；改名后本地完整跑一次 Direct 出包再提交。
- **[增量汇总引入正确性回归（聚合数对不上）]** → B4 落地前先补单测固化现状口径（给定分钟数据 → 期望小时/日聚合），改造后同一组断言必须通过；另加一条"删除后聚合修正"用例。这是本变更风险最高项，故排在 CI（B3）就位之后。
- **[DDC 重放在窗口结束时机不当（显示器尚未就绪）]** → 复用抑制门既有的"就绪"判定；重放失败不重试、等下一次用户操作（与现状"最后写入为准"的语义一致）。
- **[竞态协调器抽取引入新竞态]** → C2 落地后，按提交历史中的三个既有竞态场景（展开中收起、动画中采样刷新、快速双击）手动回归两渠道面板；该变更独立提交便于回滚。
- **[深链兜底重放造成标签页"跳变"观感]** → 观察者消费后立即清除待处理值，窗口已在前台的二次打开走正常路由，无跳变。
- **[看门狗超时误杀慢采样]** → 8s 上限远超 nettop/ps 常态 1-2s；误杀后果仅为该次列表不更新，无数据损失。

## Migration Plan

无数据迁移。发布顺序即批次顺序：A（随下个正常版本）→ B（CI 就位后再发下一版）→ C（独立提交逐步合入）。`HagimiMonitorDirect` 产物改名自 Direct 渠道下个版本生效；已安装用户的旧版 `.app` 路径由 Sparkle 常规替换处理（更新包全量替换，不涉及路径迁移）。回滚策略：每批次独立提交，单独 revert 无依赖。

## Open Questions

- UITests target（当前死重、无 scheme 可执行）保留还是删除——不阻塞任何批次，B2 核查时顺带决定即可。
- gh-pages 孤儿 `privacy.html`（H5）是否要保留为站点页——删除前确认无外部引用。
