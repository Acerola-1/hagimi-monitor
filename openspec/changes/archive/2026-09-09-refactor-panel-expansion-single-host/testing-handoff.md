# 面板动画测试交接

日期：2026-09-06。工作目录：`/Users/acerola/Dev/Swift/hagimi-monitor`。

后续更新：交回报告已完成[证据复核](handoff-review.md)。零边界实现和显示器父子迁移已通过新的协调器回归及 196 项全量测试，详情见 [verification.md](verification.md)。以下步骤仍用于原生和性能验收；历史报告不代表这些步骤已全部完成。

## 给测试 agent 的任务

请验证当前工作区的面板动画改动，重点回答：**真实 60Hz 下，展开/收起时窗口底边是否仍分段跳动；窗口、卡片和底部留白是否在实际画面中同步；快速反转是否连续。** 先测试、保留证据并报告问题，不提交、不重置工作区、不开始全量迁移。必要的诊断或回归测试请单独记录。

先读仓库 `AGENTS.md` 和本 change 的 `design.md`、`tasks.md`、`verification.md`。当前分支为 `codex/panel-expansion-single-host`，基线提交 `756b1975`，实现包含未跟踪文件；只取 Git HEAD 会漏掉被测实现。记录工作区状态及被测源码摘要。

**当前候选只是 CPU/GPU/内存三卡片原型。** 必须设置 `HAGIMI_PANEL_SINGLE_HOST=1` 才启用。未设置或设为 `0` 仍走旧实现。其他模块和显示器嵌套区域尚未迁移，不能作为候选已通过的项目。

## 1. 环境与构建

1. 保持 Mac 已解锁、面板可见且无遮挡。上次原生画面采集被锁屏阻断，尚无完成解锁的确认。
2. 记录 macOS/build、芯片、显示器、逻辑分辨率、backing scale、实际刷新率、低电量模式与电源状态。已有机器记录为 M4、macOS 27.0、DELL S2725QC 120Hz。
3. 让用户将被测屏设为 **60Hz**，或取得明确授权后设置，结束恢复原值。此前改变刷新率的询问尚未得到答复；文件名中的 `60` 和 `HAGIMI_PANEL_AUTOTEST=120:1` 都不会设置刷新率，后者的 `120` 是秒。
4. 性能测试期间只运行一个被测实例；记录自己的 PID，退出时只清理自己的进程。不要用宽泛的 `pkill` 关闭用户应用。构建、测试、截图和其他性能工具不与 Time Profiler 采集并行。
5. **重新构建并重跑测试。** 最近加入的窗口可见性检查、首次几何准备回调尚未完成构建/运行验证；历史 182 项通过不代表最新源码通过。

以下命令均从仓库根目录执行。测试只用 Direct scheme，保留退出码、日志和 `.xcresult`：

```bash
mkdir -p tmp/panel-single-host

xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath tmp/dd-review-single-host \
  -clonedSourcePackagesDirPath tmp/dd-direct/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  test > tmp/panel-single-host/handoff-tests.log 2>&1

xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath tmp/panel-single-host/dd-candidate \
  -clonedSourcePackagesDirPath tmp/dd-direct/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGN_IDENTITY='Apple Development' DEVELOPMENT_TEAM=VTQ6S5M4K3 CODE_SIGN_STYLE=Manual \
  build > tmp/panel-single-host/handoff-release-build.log 2>&1
```

Release 签名参数来自本机已成功的构建；换机器应使用其有效签名。此前 ad-hoc 签名导致 Sparkle 因 Team ID 不匹配无法加载，不要通过关闭库验证或 hardened runtime 绕过。若缺依赖缓存，使用正常包解析并记录。重跑请换日志名，保留上一次失败证据。

## 2. 先看画面：底边、收尾和反转（最高优先级）

使用新构建的 Release，先无负载观察，再在真实 60Hz 和可复现负载下重复。手动交互模式只设置实验开关：

```bash
HAGIMI_PANEL_SINGLE_HOST=1 \
  tmp/panel-single-host/dd-candidate/Build/Products/Release/HagimiMonitorDirect.app/Contents/MacOS/HagimiMonitorDirect
```

让启动命令在持续存活的终端/工具会话中运行，然后从菜单栏打开面板；不要后台启动后立即结束父会话，工具可能清理子进程。确认实际运行的是该产物，避免 UI 工具重开成未带环境变量的副本。

| 操作 | 次数/条件 | 观察与验收 |
| --- | --- | --- |
| 单独展开、收起 CPU，再测 GPU/内存 | 每行至少 10 轮，等动画结束 | 顶边锚定，底边连续移动；没有中途停住再追赶、末尾补跳、底部空洞 |
| 同时开关三行 | 双击 `SYSTEM · LIVE`，至少 10 轮 | 后续卡片、Footer、外框同向同步；多行高度相加不产生额外台阶 |
| 动画中反向点击 | 约 100ms 间隔，至少 20 次 | 位置不跳，保留运动惯性，无瞬间反向或重新从静止启动 |
| 收起接近结束时重新展开 | 覆盖约 0.22–0.28s 附近，以实际零交叉时刻为准 | 专查临近零揭示时速度被提前清零、尾段顿挫；精准时序由协调器测试补充 |
| 完全收起后停留 | 放大检查每张卡片 | 行头完整；明细、黑线、核心环均无 1 像素漏出 |
| 首次打开与动画中关闭重开 | 冷启动立即点击、连续开关、运动中点外/按 Escape | 无零高闪现、无法打开、迟到回调重新弹出或错误高度 |

保留独立连续画面，覆盖开始、中段、反转及收尾。记录捕获方法、实际采样率、是否丢帧；至少覆盖每个 60Hz 刷新周期，外部高帧率拍摄可补充屏幕录制。逐帧标记窗口顶/底边、卡片底边与 Footer 的位置，检查它们是否有可重复的先后变化。软件提交日志、相同 frameID、单张截图均不能证明 WindowServer 最终呈现同步；录制本身掉帧则该段结论不确定。

对照旧入口的同状态画面，核对：面板 340pt、卡片 328pt、左右各 6pt、顶部 8pt、底部/行距 6pt、卡片圆角 14pt、外框 continuous 20pt、原明细缩进与行头。截图像素需按 backing scale 换算；几何边界与抗锯齿过渡分别判断。核对亮暗模式的统一玻璃、透光、高光及原生阴影。

## 3. 性能对照：同产物、同数据、紧邻运行

已有脚本位于本地 `tmp/panel-single-host/`，不在 Git 中；先确认文件存在：

- `record_benchmark.sh`：参数依次为唯一名称、入口 `0/1`、CPU worker 数、模式 `single/all/reverse`。
- `cpu_load.py`：生成限时负载，输出实际 CPU 时间和核当量，不把 worker 数当成实际占用核数。
- `analyze_operations.py`：逐操作对齐 Time Profiler 样本。
- `real-fixture.json`：从本机真实数据捕获的固定输入，含进程信息，仅本地使用，不上传、不提交。记录其 SHA-256，两入口必须用同一文件。

物理刷新率确认 60Hz 后，按以下顺序串行执行。每条结束确认成功再继续；名称已存在时换一组新名称，不能覆盖旧 trace。建议再以候选→基线的顺序重复一组，减少运行顺序和温度影响。

```bash
bash tmp/panel-single-host/record_benchmark.sh handoff-baseline-normal-60 0 0 single
bash tmp/panel-single-host/record_benchmark.sh handoff-candidate-normal-60 1 0 single
bash tmp/panel-single-host/record_benchmark.sh handoff-baseline-load8-60 0 8 single
bash tmp/panel-single-host/record_benchmark.sh handoff-candidate-load8-60 1 8 single
```

每轮自动执行 50 次操作：丢弃前 10 次（5 轮预热），剩余 20 次展开、20 次收起。检查日志有全部 `operation=0…49`、每次 `unoccluded=1` 和最终 `complete`，无 `fixture-error`、`aborted=window-occluded`、崩溃或隐藏。可见性检查只在操作起点进行，仍需保证整个序列无遮挡、未锁屏。

补测 `all` 和 `reverse`，两入口条件对应一致；`reverse` 间隔为 100ms，不把重叠的 550ms 动画窗口当独立样本。先使用 8 workers；若不能复现原始阻塞，记录“未复现”，再根据栈与场景调整，不能单纯增加系统负载就宣称复现了原布局问题。

导出示例（替换 `panel_run_name`，对每轮执行）：

```bash
panel_run_name=handoff-baseline-normal-60
xcrun xctrace export --input "tmp/panel-single-host/$panel_run_name.trace" \
  --toc --output "tmp/panel-single-host/$panel_run_name-toc.xml"
xcrun xctrace export --input "tmp/panel-single-host/$panel_run_name.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output "tmp/panel-single-host/$panel_run_name-time-profile.xml"

python3 tmp/panel-single-host/analyze_operations.py \
  handoff-baseline-normal-60 handoff-candidate-normal-60 \
  handoff-baseline-load8-60 handoff-candidate-load8-60 \
  --output tmp/panel-single-host/handoff-operation-comparison.json
```

分别报告：

- 每次操作主线程 CPU 样本 p50/p95/p99，`StackLayout.placeChildren`、`sizeThatFits`、窗口 `setFrame` 栈的 inclusive 样本；这些类别会重叠，不能相加当总耗时。
- 稳定内容预热后自然测量次数，以及兄弟内容是否收到变化的自然尺寸提议。
- 独立呈现/帧间隔证据与慢帧归因，区分应用布局阻塞和系统调度。现有 4ms 主队列探针只记录大于 8.3ms 的间隔，既不是显示帧，也不是完整分布，不能拿它计算“屏幕帧 p95”。

计划门槛包括递归布局耗时降低至少 50%、原有可归因的 40–50ms 阻塞消失、实际窗口/内容无可重复错帧。**如果基线没复现原始阻塞，只能确认已测场景的收益，不能判定该问题消失。** 既有 120Hz 数据没有复现该阻塞，且未同时记录窗口遮挡状态，需重新采集。

## 4. 封顶滚动与真实交互

用 `HAGIMI_PANEL_BENCH_CAP=300` 强制 300pt 上限，分别运行两入口。自动封顶测试示例：

```bash
HAGIMI_PANEL_BENCH_CAP=300 bash tmp/panel-single-host/record_benchmark.sh handoff-baseline-cap-60 0 0 all
HAGIMI_PANEL_BENCH_CAP=300 bash tmp/panel-single-host/record_benchmark.sh handoff-candidate-cap-60 1 0 all
```

手动测试则在第 2 节的直接启动命令前额外设置 `HAGIMI_PANEL_BENCH_CAP=300`，**不设置 `HAGIMI_PANEL_BENCH`**。后者会冻结输入、自动切换并抑制点外/失焦关闭，不能用于正常事件验收。

依次测试：

1. 三行同时展开跨过高度上限：窗口停在上限，Header 固定，Footer 随主体滚动，最后一个新展开目标可见。
2. 自动揭示过程中向反方向滚动，分别用滚轮和触控板惯性：立即连续接管，无偏移争夺或停止手势后被拖回。
3. 滚到底部收起最后一行，再全部收起：偏移正确收回，无底部空洞、第二段追赶、渐隐闪烁。
4. 部分揭示时点击可见与被遮住的区域；收起后 Tab/Shift-Tab、Space/Return、VoiceOver 遍历：不可见内容不能命中或获得焦点，行头仍可操作。
5. 去掉封顶参数，以真实采样运行，改变主题、语言和可用的内容显示设置：内容继续更新，尺寸只在结构变化时失效，无错行/陈旧高度。没有真实数据的模块仍按既有方式降级。

## 5. 双面板、生命周期与渠道回归

- 同时打开菜单栏和钉住面板，交替展开：状态/速度/滚动互不牵动，钉住窗口顶部位置正确，content/frame 换算无标题栏额外高度。
- 动画中隐藏、重开、拖动钉住窗口、换屏；切换减少动态效果并恢复：没有迟到尺寸写入、遗留时钟或关闭后重现。系统设置变更应获得相应授权。
- 分开进行内存采集：记录预热后可见值、50 次切换后、隐藏并等待稳定后，以及 25 次关闭重开后的 footprint/保留对象；与旧入口同条件比较。区分缓存稳定平台和每轮累积泄漏。
- 检查动画收敛/隐藏后 display link 停止，真实采样恢复，不因持续点击留下永久刷新门控。
- 分别构建两个 Debug 渠道，再按同样的实验/普通入口验证启动、玻璃、阴影、点外关闭；测试仍只运行 Direct scheme。

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-appstore \
  build > tmp/panel-single-host/handoff-appstore-build.log 2>&1
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-direct \
  build > tmp/panel-single-host/handoff-direct-build.log 2>&1
```

当前产物名分别是 `HagimiMonitor.app` 与 **`HagimiMonitorDirect.app`**，后者与 AGENTS 的旧启动示例不同。App Store 的沙盒可能不能读取仓库中的夹具，双渠道手测使用正常真实采样，不因夹具路径失败就改沙盒权限。最后清理测试负载和实验实例、恢复经授权修改的设置，并启动正常的两个 Debug 版本供用户观察。

## 6. 已知重点与结果格式

以下是待验证风险，不是已完成项：

- `SingleHostMotionCoordinator.sampleTracks` 已将解析衰减与可见零边界分离，新增真实协调器测试覆盖过零反转、迟到采样及几何换版。仍需验证修复后的原生收尾、反转画面与性能，不能以单元测试代替。
- 最新 `awaitingGeometry` / `geometryDidPrepare` 路径需验证冷启动和快速取消，尚未跑最新构建。焦点转移也尚未完整实现。
- `display: false` 与布局提交顺序只有软件层证据，尚未完成实际呈现对照。当前没有用于切换 `display: true/false` 的环境变量；需要对照时用隔离的诊断改动并清楚标记，不能虚构开关或直接改正式入口。
- 钉住面板的屏幕封顶接入、完整模块和真实显示器嵌套迁移未完成；纯几何测试通过不替代这些原生场景。
- 缺少 macOS 15/26、真实 60Hz、低电量环境或辅助功能操作能力时标记“未测/受阻”，不要代填通过。

请输出 `tmp/panel-single-host/handoff-results.md`，至少包含：

1. 被测源码/产物、环境、入口参数、固定输入摘要和真实负载记录。
2. 用例表：操作、预期、实际、通过/失败/未测、原始证据路径。
3. 底边顿挫的结论与可复现步骤；视频时间点/帧号、代码位置和支持归因的栈，分别标明实测与推断。
4. 基线/候选性能表，明确“操作 CPU 样本”“主队列间隔”“实际呈现帧”三种口径。
5. 最新测试和双渠道构建结果、剩余阻塞及是否满足三卡片迁移门槛。

优先交付第 1–3 节结果，再补齐事件/生命周期矩阵。即使递归布局收益达标，只要窗口底边仍可重复跳动、存在裁切/漏像素或反转断速，整体门槛仍未通过。
