# HagimiMonitor 需求分析报告：电源流向图改造 × 功能扩展头脑风暴

> 日期：2026-08-15 ｜ 性质：需求分析 / 头脑风暴（非实施规格）
> 大前提：**App Store 版（沙盒）与 GitHub Direct 版（无沙盒）能力边界不同，所有方案均按双渠道分开评估。**

---

## 0. 双渠道能力边界（全文判断依据）

| 维度 | App Store 版 | GitHub Direct 版 |
|---|---|---|
| 沙盒 | `ENABLE_APP_SANDBOX = YES` | 关闭，Developer ID + 公证 |
| IORegistry **只读**（AppleSmartBattery / PowerTelemetryData / SMC 读数） | ✅ 允许（现有功率流即此路径） | ✅ |
| SMC / 系统**写入**（充电限制、风扇转速、亮度原生接口） | ❌ 不可上架 | ✅（需自研 helper 或直接调用） |
| DDC/CI 外接显示器控制、媒体键劫持、Gamma 调光 | ❌（已从 target 排除） | ✅（`HagimiMonitorDirectOnly/`） |
| 进程级采样（top CPU/内存/磁盘/网络进程） | ✅ 现状已有 | ✅ |
| 本地通知 / App Intents / Foundation Models | ✅ | ✅ |
| Accessory Access 框架（macOS 27 新） | ❌ 官方已知问题：沙盒内不可用 | ✅（但价值低，见 §2.2 C） |

**核心结论：电源流向图的改造完全在"只读数据"范畴内，两渠道可共用同一套实现，无需分叉；分叉只出现在"控制类"新功能上。**

---

## 1. 电源模块流向图：诊断与改造方案

### 1.1 现状诊断

当前实现（`MonitorPanelView.swift` 的 `PowerFlowDiagram`，图高 118pt）：

- **结构**：适配器 → 汇流点 → 系统（上排左右节点），电池在正下方，三角形布局；Canvas 粒子沿线流动（数量/速度 ∝ 瓦数），充电时电池节点呼吸辉光；图下一行 ETA 文案。
- **数据链**（`BatterySampler`）：`power-in`（SystemPowerIn）、`power`（SystemLoad）、`battery-flow`（BatteryPower 带符号）、`status`、`time-remaining`、`adapter`（额定瓦数）。
- **门控**：设置项 `batteryShowPowerFlow`（Beta）；无 `power` 数据的老机型整体隐藏。

**你感觉"信息少、空、一般"的客观成因：**

1. **面积利用率低**：三角形布局中间大片空白；idle 态（插电满电直供）电池边只剩暗轨道，下半图几乎全空——而这是桌面用户/满电用户最常见状态。
2. **电池节点不承载电量**：电量百分比只在行头 summary 出现，图里的电池只是一个文字节点，没有"容器感"，与 82% 这个最关键信息脱节。
3. **三条边粗细一致**：粒子数最多 5 颗，"流量大小"表达弱；输入 58W 与输出 24W 在视觉上无差异。
4. **信息面窄**：图上只有 3 个瓦数 + ETA。已有但没上图的数据：转换损耗（可算：power-in − system − |battery-flow|）、适配器额定负载率（power-in / adapter 额定）、电压/电流（BatteryData 有）、温度、充电限制。
5. **无时间维度**：只有瞬时值，看不出"刚才发生了什么"（插拔、负载突增）。
6. **"电去哪了"没闭环**：系统负载 24W 是个黑盒，没有下钻（这正是 `prototypes/power-flow/index.html` 里"耗电排行"区块 B 想做而未落地的）。

### 1.2 已有原型资产（别浪费，直接选型）

`prototypes/power-flow/` 已有 6 个候选，按方向归类：

| 文件 | 方案 | 特点 |
|---|---|---|
| `index.html` | v2 三节点 + **耗电排行** | 信息最全，含进程估算+子系统实测对平 |
| `battery-bar.html` | **全宽电量条**：上排适配器─汇流─系统，电池变全宽条（填充=电量），ETA 收进条内 | 电池永远承载信息，idle 态不空；图高可压到 94 |
| `compact.html` | 单行母线三方块，导管粗细 ∝ 瓦数 | 最省高度 |
| `alternatives.html` | Sankey 桑基流（含损耗分支） | 信息强但视觉重，当时对标 AlDente 刻意避开 |
| `candidates-de.html` | 候选 D/E | 非 Sankey 中间路线 |
| `candidates-fg.html` | 候选 F/G | 非图表、非流向图（纯数据排布） |

### 1.3 推荐改造方案（组合式，按增量排序）

**方案 P1-A｜全宽电量条为主体（推荐基座）**
采纳 `battery-bar.html`：电池从"节点"升级为"全宽容器"，填充=电量百分比，充电/放电的流向短 stub 垂直连入条内。收益：
- idle/满电直供态下电池条依然显示 100% 填充 + 状态文案，**任何状态都不空**；
- 电量与流向第一次在同一视觉元素里表达；
- 条内左侧电量+状态、右侧 ETA 走 flex 两端对齐（原型 v3 验证最窄场景仍有 ≥59px 富余，构造上不会重叠）；
- 实现约束：节点用流式布局、连线按 DOM 实测坐标绘制，禁止固定宽度硬编码（v2 原型曾因 296px 固定宽溢出导致重叠）。

**P1-B｜边的瓦数视觉编码**：导管粗细 ∝ 瓦数（compact.html 做法），输入粗、输出细一眼可辨；适配器不足（insufficient）时电池补电边用 warning/crit 色。

**P1-C｜图上信息增补（数据现成，零新采样）：**
- **转换损耗**分支或角标：`power-in − system − |battery-flow|`，可算出 2~4W 损耗；
- **适配器负载率**：适配器节点加细进度条（实际输入 / 额定瓦数），逼近 100% 变 warning 色——直接预警"适配器不足"场景；
- **充电限制线**：电量条上标出当前充电上限刻度（80%/100%）——macOS 15+ 系统有充电限制设置，读 `ChargeLimit` 类 registry 键（需在 macOS 27 上验证键名，BatteryData 迁移后可能挪位）；
- 电池温度 ≥ 阈值时电池条描边换 warning 色（数据已有）。

**P2-A｜耗电排行（闭环"电去哪了"）**：落地 `index.html` 区块 B——
- 进程能耗估算行（复用现有 top 进程采样，CPU 能耗 ≈ CPU 占用 × 系统负载估算）；
- 子系统实测行：IOReport / `PowerTelemetryData` 中的分域功耗（如可读），合计对平系统负载；
- **渠道**：全部只读，两渠道通用。这是从"展示功率"升级为"解释功率"的关键一步，也是与 Stats/iStat 的差异点。

**P2-B｜60s 功率 sparkline**：系统功率迷你历史曲线（复用 `SparklineChart`），放电量条上方或取代 ETA 行位置，提供时间维度。

**场景矩阵（必须全覆盖，避免"样式空"复发）：**

| 场景 | 现状表现 | 目标表现 |
|---|---|---|
| 充电中 | 正常 | 条内填充爬升 + ETA 充满 |
| 电池供电 | 正常 | 条内填充流出 + ETA 可用 |
| 适配器不足 | 无特殊视觉 | 双源汇入、crit 色、文案提示 |
| 插电满电直供（idle） | **下半图空** | 电池条 100% 满格 + "直供"状态语 |
| 无电池台式机（mini/Studio/Pro） | 三节点缺电池边，布局失衡 | 降级为两节点 + 功率 sparkline，不渲染电池元素 |

**动画预算提醒**：现有"粒子动画只驱动 Canvas、仅面板可见且展开时 animate"的策略是对的（CollapsibleDetail 常驻挂载），改造时保持该约束，电量条填充变化用 `.animation` 插值即可，不引入常驻 TimelineView。

**渠道结论：§1.3 全部为 IORegistry 只读 + 纯 UI，App Store / Direct 共用同一实现，无分叉。**

---

## 2. 功能扩展：差距盘点与建议

### 2.1 已有能力与在途项（避免重复立项）

**已上线**：CPU/GPU/内存/存储/网络/电池/风扇七模块、展开详情与 top 进程、统计持久化（基础）、液态玻璃主题、流体面板/钉住、菜单栏负载环、Sparkle 更新（Direct）。
**Direct 独有已上线**：DDC 外接显示器亮度/音量/对比度、媒体键接管、Gamma 调光、音频输出检测。

**在途（openspec/changes 已有 proposal，本报告不再重复展开）：**
- `add-menu-bar-metric-display`（菜单栏多指标显示）
- `enhance-statistics-data-collection`（统计维度扩展：swap/VRAM/温度/电池统计）
- `event-timeline`（事件检测 + **告警通知**——竞品 Stats/iStat 都有告警，这是当前最大空白之一）
- `mac-health-score`（健康评分）
- `menu-bar-quick-tools`（键盘锁/防休眠，已设计暂缓）
- `adopt-liquid-glass`（液态玻璃回归，已验证暂缓）

### 2.2 新增功能建议（按渠道 × 优先级）

#### A. 双渠道通用（沙盒安全，只读/公开 API）

| # | 功能 | 说明 | 优先级 | macOS 27 关联 |
|---|---|---|---|---|
| A1 | **热压力指示器** | `ProcessInfo.thermalState`（nominal/fair/serious/critical）上 CPU 行或健康分区；serious+ 变色。节流是 Mac 用户最痛的点，现完全没量化 | ★★★ | 无（老 API，但 27 主打性能优化，热度话题性高） |
| A2 | **Rosetta 转译进程标记** | top 进程列表标注 `P_TRANSLATED`（sysctl 每进程查询），菜单/面板提示"这些 Intel 应用将在 macOS 28 无法运行" | ★★★ | ★ 强关联：27 是 Rosetta 完整支持的最后一年，系统设置已列 Intel 应用清单，话题正当时 |
| A3 | **低电量模式 / 充电状态语义** | 显示 Low Power Mode 是否开启（影响性能与充电策略），纳入电源模块上下文 | ★★ | — |
| A4 | **App Intents / 快捷指令暴露指标** | "获取 CPU 占用"等 intent，可被快捷指令/Spotlight/27 的 AI 快捷指令引用 | ★★ | ★ 27 的快捷指令支持自然语言创建，指标可入自动化 |
| A5 | **CPU 细分**：P/E 核占用、频率（host_processor_info + sysctl）；**内存压力等级 + swap**（部分已在 enhance-statistics 在途） | 提升单模块信息密度 | ★★ | — |
| A6 | **Wi-Fi 信号质量/延迟**：CoreWLAN RSSI + 可选 ping 网关 | 网络模块现只有速率 | ★ | CoreWLAN 在沙盒下 XPC 需实测验证 |
| A7 | **存储 SMART 状态 / 卷级用量** | StorageSampler 现偏重 IO 速率 | ★ | — |
| A8 | **AI 摘要（Foundation Models 本地模型）** | "为什么 CPU 高"用本地模型结合 top 进程+事件生成一句话解释 | ☆ 观察 | ★ 27 主推 Core AI；但依赖 Apple Intelligence 可用性（中国大陆不可用），建议做成可选实验项，不作为主线 |

#### B. Direct 版独有（无沙盒才能做，作为 GitHub 版付费点/差异化）

| # | 功能 | 说明 | 优先级 |
|---|---|---|---|
| B1 | **充电限制控制**（AlDente 式） | 写 SMC/系统接口设置 80% 上限。需自研特权 helper（LaunchDaemon）或直接 SMC 写（后者稳定性风险高）。电池养护是刚需，竞品 AlDente 单点立足 | ★★★（Direct 王牌） |
| B2 | **风扇转速手动/曲线** | SMC 写 `F0Md`/`F0Tg`；已有风扇读数基础（FanSampler/SMC.swift） | ★★ |
| B3 | **一键性能模式切换** | 低电量模式开关、`pmset` 相关只读+受控写 | ★ |
| B4 | 现有显示控制延伸：**显示器信息面板**（分辨率/刷新率/HDR 状态） | 27 支持 5K120 超宽屏，信息展示两渠道可做，**控制**保持 Direct | ★ |

#### C. 明确不建议做

- **Accessory Access 框架**（27 新）：沙盒内不可用（官方 known issue），且对监控类应用无实际数据价值；
- **跟随系统 Liquid Glass 透明度滑块的自定义实现**：系统滑块自动作用于标准 glass 材质，无需自建；面板若用自定义透明度设置则另说（属现有配色体系的延伸，非 27 特性）。

### 2.3 macOS 27 专项挖掘清单

| 27 变化 | 对本项目的含义 | 行动 |
|---|---|---|
| 纯 Apple Silicon（Intel 出局） | 与 arm64-only 定位完全对齐；目标用户群无缩水 | 无需动作，营销点 |
| **BatteryData registry 布局迁移**（根节点键挪到 AppleSmartBatteryPack） | `BatterySampler` 已用子树合并兜底（26/27 双兼容） | ✅ 已处理；新增任何电池键（如 ChargeLimit）必须走同一 `lookupDouble` 路径并双系统验证 |
| **菜单栏折叠功能** | 在途的"菜单栏多指标显示"必须测试折叠态下 label 截断行为 | 列入 add-menu-bar-metric-display 验收项 |
| Rosetta 2 进入倒计时（28 只剩游戏） | A2（转译进程标记）的时效性红利 | 尽快做，27 周期内最有话题性的差异化 |
| Metal 4.1 | GPU 采样（IOAccelerator）回归测试 | 每次 beta 跑一次 |
| 系统 Liquid Glass 透明度用户滑块 | `adopt-liquid-glass` 在途项落地后自动受益 | 无需额外动作 |
| Foundation Models / Core AI | A8 观察项；有 region 限制与 beta 稳定性问题（release notes 多条 known issue） | 不纳入主线 |
| 屏幕录制支持系统声音、下拉刷新、iPhone 镜像比例调整等 | 与监控定位无关 | 跳过 |

---

## 3. 落地优先级建议（个人判断，供拍板）

**第一波（一个版本内）**
1. 电源流向图换基座：battery-bar 全宽电量条 + 边宽编码 + 损耗/适配器负载率增补（§1.3 P1）——解决"空、信息少"的直接诉求，双渠道同版；
2. 热压力指示器（A1）——小改动大感知；
3. Rosetta 进程标记（A2）——吃 27 时效红利。

**第二波**
4. 耗电排行（§1.3 P2-A）——电源模块从展示到解释；
5. event-timeline 告警（在途）+ 健康评分（在途）；
6. 菜单栏多指标（在途，注意 27 菜单栏折叠兼容）。

**第三波（Direct 差异化）**
7. 充电限制控制（B1，helper 方案先行调研）；
8. 风扇曲线（B2）。

---

## 4. 风险与验证点

1. **ChargeLimit 键位**：macOS 27 BatteryData 迁移后需实测键名与层级；读不到则充电限制线降级为"80/100 系统语义提示"。
2. **IOReport 分域功耗**（耗电排行的"硬件实测"部分）：沙盒下 IOReportMaster 可读性需在两渠道分别实测；不可读则只保留进程估算并注明口径。
3. **CoreWLAN 沙盒**：A6 立项前先做 spike。
4. **SMC 写入（B1/B2）**：涉及系统电源管理安全，必须 helper + 权限引导 + 失败回退；且永远不进 App Store target（沿用 `DIRECT_DISTRIBUTION` 编译开关纪律）。
5. **动画性能**：任何流向图改版维持"动画封闭在 Canvas、仅可见且展开时驱动"的既有纪律。

---

## 5. 评审结论（2026-08-15 用户确认）

| 项 | 结论 | 去向 |
|---|---|---|
| 电源流向图改造 | ✅ 采纳（battery-bar 全宽电量条基座 + 边宽编码 + 信息增补 + 场景矩阵） | 原型见 `prototypes/adopted-features/index.html` 电源行展开区 |
| A1 热压力指示器 | ✅ 采纳（经原型可视化演示后用户确认；展示形态定为明细网格内一格 + severity 配色，非浮动芯片） | 原型 CPU 行展开区 |
| A2 Rosetta 进程标记 | ✅ 采纳 | 原型 CPU 行展开区（TOP 进程列表） |
| A3 电源状态区分 | ✅ 采纳（用户确认现状电源栏未区分状态，四态四色行头芯片） | 原型电源行行头 |
| A4 App Intents + A8 AI 摘要 | ✅ 采纳但暂缓，合并为一个 openspec 计划，等国行 Apple Intelligence 上线后立即执行 | `openspec/changes/ai-insights-and-intents/`（Hold 态；A4 不依赖 AI，可拆出先行） |
| A5 CPU P/E 细分 + 内存压力 | ✅ 采纳 | 原型 CPU/内存行展开区 |
| A6 Wi-Fi 信号/延迟 | ✅ 采纳（CoreWLAN 沙盒 spike 先行） | 原型网络行展开区 |
| A7 存储 SMART/卷用量 | ✅ 采纳 | 原型存储行展开区 |
| B1 充电限制控制 | ❌ 放弃（macOS 26.5+ 官方已提供充电限制，无需自研控制；仅保留只读展示限制刻度） | 原型电量条内刻度线 |
| B2 风扇转速控制 | ❌ 采纳后撤销（落地实测：用户态写 SMC 被系统拦截，控制无法生效，已整体移除） | — |
| B3 性能模式切换 | ❌ 不考虑 | — |
| B4 显示器信息面板 | 🔶 可考虑（信息展示两渠道，控制仍 Direct） | 原型显示器行展开区 |

配套产物：
- 可交互原型：`prototypes/adopted-features/index.html`（v3：完全复刻真实面板 UI——行/双列明细网格/双 pill/28pt 缩进/MonitorPalette 配色，行可点击展开；含场景/热压力/渠道三组演示开关）；
- 暂缓计划：`openspec/changes/ai-insights-and-intents/`（proposal / design / tasks / spec 四件套）。

---

## 6. 实施记录（2026-08-16，原型冻结后落地）

### 已实现（双渠道构建通过）

| 原型项 | 实现 | 关键文件 |
|---|---|---|
| 电源流向图改造 | 全宽电量条基座（填充=电量/充电限制刻度/左电量状态右 ETA/状态边框色）+ 双节点 + 导管粗细∝瓦数 + 适配器额定负载率细条 + 五场景说明行 + 台式机降级直通线；纯静态 Canvas 绘制，无粒子动画、无 TimelineView | `MonitorPanelView.swift`（PowerFlowDiagram 重写） |
| 电源新增明细 | 转换损耗（输入−系统−|流向| 钳零）、充电限制（IORegistry 尽力读）、低电量模式 | `BatterySampler.swift` |
| 60s 功率 sparkline | 新增 `MonitorModule.powerSamples` 滚动历史通道 + avg 读数，复用 SparklineChart | `SystemMonitorSampler.swift` |
| A3 状态芯片 | 四态四色（含派生态「适配器不足」：插电但电池放电补差），浅深色两套校准 | `BatteryGlassRow` / `BatteryPowerStateChip` |
| A1 热压力 | ProcessInfo.thermalState 四档进 CPU 明细网格，按 severity 着色 | `CPUSampler.swift` + `MetricDetailGrid` |
| A5 CPU 细分 | 性能核/能效核分组占用（host_processor_info 逐核差值 + hw.perflevel0/1 拓扑）；内存补「压缩」指标 | `CPUSampler.swift` / `MemorySampler.swift` |
| A2 Rosetta | sysctl.proc_translated 检测 → TOP 进程行琥珀角标 + 汇总横幅（macOS 28 兼容性提醒） | `TopCPUProcess.swift` / `CPUProcessList` |
| A6 Wi-Fi | 信号格+dBm（CoreWLAN，RSSI 10s 缓存）、网关延迟（TCP connect 计时 5s 缓存，沙盒 network.client 即可）、SSID、接口名；探针失败降级为 "--" | `WiFiProbe.swift`（新） |
| A7 SMART | system_profiler -json 的 smart_status（60s 缓存，后台队列）；verified 绿/failing 红 | `StorageSMARTProbe.swift`（新） |
| B2 风扇控制（Direct） | ❌ 已整体移除（见「评审后修复」第 1/4 条：本机实测用户态写 SMC 被系统拦截，控制无法生效） | — |
| B4 显示器信息（两渠道） | 显示器行：分辨率/刷新率/HDR（EDR headroom）；亮度与 DDC 状态仅 Direct 回填 | `DisplayInfoSection.swift` / `DisplayInfoSupport.swift` |
| 本地化 | 新增约 40 键，中/英/日全量 | `Localizable.xcstrings` |

### 取证后排除的原型单元格（无真实数据源，不伪造）

- **CPU 频率行**：Apple Silicon 无公开频率 API（CPUFreq 属 IOReport 私有通道）；
- **存储「写入寿命/磁盘温度」**：本机取证确认 system_profiler NVMe JSON 无写入量字段，Apple Silicon SSD 无 SMC 温度键。对应单元格不渲染而非显示假数据。

### 验证证据

- HagimiMonitor（App Store 沙盒）与 HagimiMonitorDirect 两 scheme `BUILD SUCCEEDED`；
- 测试套件：除 5 个 SettingsTests 既有失败外全部通过（该 5 项已在干净 HEAD 复验为在途 menu-bar-metric-display 的既有失败，与本次无关）；
- 冒烟启动：Direct 构建启动 14s 进程存活、采样正常运行，无崩溃（日志仅系统 App Intents 框架 beta 噪音）。

### 遗留注意项

- CoreWLAN 在沙盒下依赖 airportd XPC，个别环境可能降级为 "--"（不影响其余指标） ；
- 新增明细指标对已持久化过指标开关的老用户需手动在设置里勾选（项目既有约定）。

### 评审后修复（2026-08-16 晚，用户实测反馈）

1. **风扇控制已整体移除**：本机实测（Apple Silicon · macOS 27 beta，沙盒内外一致）用户态写 SMC 被内核拒绝（`kIOReturnNotPermitted`，thermalmonitord 拦截，与公开研究结论一致），B2 控制功能无法生效。已删除 `FanControlService.swift` / `FanControlSection.swift`、`SMCReader` 写入路径、相关本地化键与启动预初始化；`SMCReader` 回到纯只读。风扇转速监控不受影响。
2. **功率流说明行精简**：常规态（充电/直供/电池/无电池）不再拼长句，仅在「适配器不足」警示态保留一行短文案；对应删除 4 个长文案本地化键。
3. **电源模式指示**：低电量模式开启时电源行行头电池图标整体染成琥珀色（`severityTint(.warning)`，SF Symbols 为模板图无需单独黄色符号）+ 悬停提示；数据源 ProcessInfo，每秒随采样刷新。
4. **风扇行展开门控回退**：单风扇不再可展开（回到提交版原逻辑：仅多风扇可展开，展开区只展示各风扇 RPM）。
