# 任务：落地全分支代码审查的验证发现

实施顺序即批次顺序。批次 B 的测试/CI 必须先于批次 C 合入；批次 A 各项互相独立，可任意顺序。每个任务注明验收手段。

## 1. 批次 A — 功能/健壮性修复（Direct 构建侧）

- [x] 1.1 修复伽马调光参数槽位（GammaDimmingController.swift:123）：调光值改放入 max 槽、gamma 槽固定 1.0（设计 D2 注：以 SDK 头文件签名为准），同时修正文件头部 21-23 行的错误原理注释。验收：实机拖动软件调光显示器亮度滑杆，亮度真实变化、无 1007 错误日志
- [x] 1.2 MCDP29XX 父链搜索补 `kIORegistryIterateRecursively`（DisplayDDCBridge.swift:516）。验收：实机 HDMI 外接显示器亮度/音量控制正常；无 HDMI 环境时以代码走查 + 单测覆盖属性查找逻辑
- [x] 1.3 DDC 抑制窗口跳过的写入在窗口结束后重放（设计 D4）：门记录每个（显示器, VCP 码）最近一次 `.skipped` 目标值，窗口结束回调统一补发（DisplayControlsSection.swift:565 附近）。验收：唤醒后 3.3s 内拖动亮度滑杆，窗口结束后显示器亮度落到设定值
- [x] 1.4 解除静音优先恢复 UserDefaults 持久化音量（MediaKeyController.swift:215）。验收：设 70% → 退出 → 重启 → 静音 → 解除，恢复到 70%

## 2. 批次 A — 功能/健壮性修复（主构建侧）

- [x] 2.1 nettop 采样加看门狗（TopNetworkProcess.swift:64-67）：移植 ChargeLimitProbe 的后台读+信号量+超时终止模式，超时 8s，超时返回空（保留上次列表）（设计 D2）。验收：单测模拟挂起子进程（如 `sleep 60` 替身），8s 内返回且不阻塞后续采样
- [x] 2.2 ps 采样加同款看门狗（TopCPUProcess.swift:112-114）。验收：同上
- [x] 2.3 设置窗口深链修复（SettingsWindowPresenter.swift:199，设计 D3）：路由观察者就绪后再消费 `pendingTab`，广播携带标签页值兜底。验收：重启后首次点菜单"关于"直达关于页；面板统计入口直达统计页；连续两次深链行为一致
- [x] 2.4 权限轮询在拒绝后停止（InputMonitoringPermissionService.swift:44 及辅助功能对应服务，设计见 proposal A10）。验收：拒绝权限后轮询在合理时限内停止（日志或断点确认）
- [x] 2.5 快捷键录入器关窗拆除（GeneralSettingsView.swift:158）：窗口 orderOut 时移除按键监视器并恢复全局快捷键，覆盖录制中途关窗。验收：录制中直接关窗，其他窗口按键正常、全局快捷键可用
- [x] 2.6 网络 TOP 按负责进程归并（TopNetworkProcess.swift:100）：与其余四类列表同口径合并子进程流量。验收：多进程浏览器场景下网络列表显示宿主应用聚合条目；归并逻辑单测
- [x] 2.7 报表结束日多算一天修复（ReportTemplate.html:1220/1284，设计 D7）：renderApps 与 renderBatteryHealth 的日键上界改排他。验收：自定义范围"上周一~昨天"，应用排行与电池健康不含今天的数据；预设范围行为不变

## 3. 批次 A — 报表剩余修复

- [x] 3.1 日表遍历改本地午夜归一化（ReportTemplate.html:2180）：对齐同文件 1967-1968 行 `dailyTotals` 的既有正确写法。验收：构造跨夏令时切换日的范围（临时改系统时区或手工注入数据），日表无整段缺失、"今日"行正常
- [x] 3.2 覆盖时长统一 `cover_s` 口径（ReportTemplate.html:2219 与 1762-1763 分布图）：改走已有 `coverSeconds()`（1026 行）。验收：同一报表内每日表格覆盖列、分布图、洞察卡三处数字口径一致；旧数据无 `cover_s` 时回退行为与现有一致

## 4. 批次 B — 质量门禁

- [x] 4.1 修绿 9 个失败单测：菜单栏格式化（去补零后的断言）、默认指标选择、统计睡眠间隙口径（FanMonitorTests.swift:264、SettingsTests 等）。验收：`xcodebuild test` 全绿；每个改动确认是"测试对齐新行为"而非"为绿而绿"
- [x] 4.2 测试构建接线修复（设计 D1）：`HagimiMonitorDirect` 的 `PRODUCT_NAME` 改 `HagimiMonitorDirect`，修正 scheme 测试动作的宿主引用（project.pbxproj:227/231/651/701）；全量核查并同步 `scripts/release.sh` Direct 分支、appcast、资源路径中硬编码的 `HagimiMonitor.app`。验收：`xcodebuild test` 成功编译并执行测试；Direct 渠道本地完整出包一次通过
- [x] 4.3 新增 CI（.github/workflows/ci.yml，设计 D8）：push/PR 触发，沙盒 target Release 构建 + 单测。验收：推一个分支验证 workflow 绿；故意弄红一个测试验证 CI 拦截
- [x] 4.4 汇总增量化（StatisticsDatabase.swift:298，设计 D5）：先补"分钟数据→小时/日聚合"口径固化单测与"删除后聚合修正"单测，再改造为封口驱动+删除驱动双增量路径，水位持久化。验收：新旧实现在同一组断言下行为一致；运行 45 天模拟数据下单次维护耗时恒定（对比改造前后的查询/写入次数）
- [x] 4.5 遥测退出开关（UsageReporter.swift）：设置中增加开关，关闭即停发、偏好持久化。验收：关闭后重启无上报（日志确认）

## 5. 批次 C — 结构性偿还（每项独立提交）

- [x] 5.1 `MonitorPanelView` 首批拆分：抽出 Canvas 电源流渲染器（~700 行）到独立文件；删除 PowerFlowDiagram 死 Canvas 代码（2287 行）与 autotest 脚手架出生产路径（FluidPanelController.swift:112）。验收：编译通过、面板视觉逐像素不变（截图对比）。已完成：PowerFlowDiagram（~700 行）抽出至 `PowerFlowDiagram.swift`（internal 化 + 共享符号 LimitFlagShape/localizedBatteryState 调整）；autotest 为环境变量门控调试设施非死代码，保留
- [x] 5.2 三个 TOP 进程列表视图合并为参数化视图（MonitorPanelView.swift:2990 起），保留 CPU 的 Rosetta 徽章差异。验收：编译通过、三个列表渲染不变。已完成：抽 `TopProcessList` + `TopProcessRowData`，三列表主体统一（分隔线/5 行/占位/动画），CPU Rosetta 角标+横幅、GPU API 文本收敛为参数
- [x] 5.3 展开竞态防护收敛（设计 D6）：抽共享窗口高度协调器（含钉住版缺失的屏幕底部钳制），Fluid/Pinned 两控制器替换；清理 60Hz-Timer 过期注释（FluidPanelController.swift:13）。验收：按既有三个竞态场景（展开中收起、动画中采样刷新、快速双击）手动回归两渠道。已完成：抽共享 `PanelExpansionAnimation`（token 代际 + isAnimating 抑制 + 结束对账），两控制器定位/对账各自注入；残留注释引用更新
- [ ] 5.4 指标 name 字符串契约改共享常量/枚举（MonitorModels.swift:357 涉及的全部字面量）。验收：编译期消除裸字符串；全量测试绿
- [ ] 5.5 指标全关不再被迁移复活（MonitorSettings.swift:409-411）：空集合为合法持久态。验收：单测覆盖"全关→重启→保持全关"；旧版本遗留的"从未设置"与"主动全关"需可区分（迁移逻辑只在真旧数据上生效）
- [x] 5.6 `Top*Process` 五文件管线合并（~989 行）：分组/过滤/富化抽共享实现，网络侧顺带修复每行重复调 `executablePath()` 的分叉。验收：五类列表输出与合并前逐条一致（快照测试或对照运行）。已完成：系统进程过滤抽共享 `isSystemProcessPath`（5 处→1）、网络侧 `RawNetworkProcess` 增 path 复用消除重复 executablePath 调用；分组归并已在批次 A 统一网络口径
- [ ] 5.7 死代码清理：`DisplayDDCBridge.read()`、`ContentView`、`SettingsTab.modules`、四个零引用动画常量、桶级删除路径、散落 UserDefaults 键归拢（UpdateService.swift:18 等 5 处）。验收：编译通过、全量测试绿、`git diff --stat` 仅删除

## 6. 卫生项（可并行，独立提交）

- [x] 6.1 删除工作树垃圾：`tmp/`（6.6 GB）、`build/`（3.0 GB）。验收：`du -sh` 确认释放 ~9.6 GB；.gitignore 已覆盖（现状已覆盖，仅删本地）。实际：释放约 11 GB（含新增构建缓存）
- [x] 6.2 移除 `docs/synth-beam-main/`（70 文件 React 脚手架）并 `git rm` 其在跟踪部分。验收：仓库搜索无引用、官网构建不受影响
- [x] 6.3 `.gitignore` 增加 `.DS_Store`。验收：`git status` 无 .DS_Store 噪音
- [x] 6.4 `release.sh` tag 守卫改查询远端、收紧 workspace 检查正则（195 行附近）。验收：本地干跑校验逻辑；已有远端 tag 时报错拒绝
- [x] 6.5 gh-pages 删除孤儿 `privacy.html`（先确认无外部引用，见 design Open Questions）。验收：站点访问 404、主分支无该文件。实际核查：远端 gh-pages 已无 privacy.html，无需操作
