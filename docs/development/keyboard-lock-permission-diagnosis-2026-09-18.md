# 键盘锁权限诊断与修复交接（2026-09-18）

键盘锁定小工具在「仅锁定内置键盘」范围下不生效的完整诊断记录、证据与修复方案。面向接手继续实施的开发者：先读第 0 节（实施状态与剩余工作）与第 2 节结论，第 3 节为实证过程（含可复现命令），第 6 节为需要产品拍板的取向。

## 0. 实施状态（2026-09-18 更新，接手先读本节）

### 已实施架构（第一轮基础架构 + 第二轮审查打磨修复）

#### 第一轮实施（核心机制恢复与健壮性）：
1. **新增 `HagimiMonitor/InputMonitoringPermissionService.swift`**：输入监控授权服务（`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`、跳转 `Privacy_ListenEvent`、拖拽引导、120 秒授权轮询），形态对齐 `AccessibilityPermissionService`。
2. **`QuickToolsStore` 双权限门控**：
   - `keyboardLockPermissionsReady`：Direct = 辅助功能 + 输入监控；App Store = 输入监控；
   - 缺失项优先引导（Direct 先辅助功能、后输入监控；补齐一项且上锁意图仍挂起时自动衔接下一项引导）；
   - 权限撤销即解锁；**锁定中补授权时自动重建 HID 监听**（`keyboardLock.refreshHIDMonitoring()`），无需重启应用；
   - `refreshKeyboardLockPermission()` 同时校准两个权限服务。
3. **`KeyboardLockController` HID 健壮性**：`setupHIDMonitoring` 检查 `IOHIDManagerOpen` 返回与匹配设备数并发布 `hidMonitoringHealthy`；新增 `refreshHIDMonitoring()`（teardown + setup + 刷新拓扑 + 清空归因证据）；渠道权限注释更新。
4. **失败可见性**：新增 `keyboardLockEvidenceDegraded`——锁定中且「仅内置」且 HID 未就绪时，浮层磁贴提示新文案 `quicktools.keyboard-lock.evidence-unavailable`（中英已录入 `Localizable.xcstrings`）。

#### 第二轮打磨与审查修复（针对审查指出的 4 项体验与时序问题）：
5. **引导浮窗（`AccessibilityPermissionGuide`）文案与自闭修复**：
   - `AccessibilityPermissionGuide` 支持传入定制的 `subtitleKey`；
   - `Localizable.xcstrings` 补齐 `quicktools.permission.accessibility.guide-subtitle`（“将应用添加到辅助功能，打开旁边的开关即可。”）与 `quicktools.permission.input-monitoring.guide-subtitle`（“将应用添加到输入监控，打开旁边的开关即可。”）；
   - `InputMonitoringPermissionService.request()` 正确接入输入监控专用副标题，不再误导用户去辅助功能；
   - `InputMonitoringPermissionService.refresh()` 在获得授权（`isTrusted == true`）时自动调用 `dismiss()` 关闭引导面板，避免浮窗残留。
6. **设置页外接键盘拓扑自动刷新**：
   - `QuickToolsStore.observeKeyboardLockPermission` 中，无论当前是否落锁或挂起，只要 `keyboardLockPermissionsReady` 变为 true 即执行 `self.refreshKeyboardTopology()`，修复了用户在设置页补授权后外接键盘卡片不自动自愈的问题。
7. **App Store 沙盒信任缓存传播延迟重试恢复（`tapRetryTimer`）**：
   - 为非 Direct 渠道恢复了针对系统沙盒的 `tapRetryTimer`（5 秒一次，上限 12 次 / 60 秒），防止刚授权完因系统 TCC 缓存尚未同步导致落锁尝试单次失败即退出的问题；在解锁、取消意图、撤销授权或 `deinit` 时均保证可靠销毁。
8. **补齐自动化单元测试**：
   - 在 `HagimiMonitorTests/KeyboardLockControllerTests.swift` 增加初始状态健康、未激活下安全刷新、拓扑扫描一致性等测试用例。
9. 变更文件清单：
   - `HagimiMonitor/InputMonitoringPermissionService.swift`（新增）
   - `HagimiMonitor/AccessibilityPermissionGuide.swift`
   - `HagimiMonitor/AccessibilityPermissionService.swift`
   - `HagimiMonitor/QuickToolsStore.swift`
   - `HagimiMonitor/KeyboardLockController.swift`
   - `HagimiMonitor/Localizable.xcstrings`
   - `HagimiMonitorTests/KeyboardLockControllerTests.swift`

### 验证状态

- **构建验证**：
  - `HagimiMonitor`（App Store 渠道）Debug 构建通过（`tmp/dd-appstore`）；
  - `HagimiMonitorDirect`（Direct 渠道）Debug 构建通过（`tmp/dd-direct`）。
- **单元测试**：
  - Direct 完整测试套件通过（`xcodebuild ... -scheme HagimiMonitorDirect ... test`，**TEST SUCCEEDED**）。
- **未做（留给接手者实机走查）**：
  - 实机 TCC 授权完整流程走查（在测试构建上撤销权限 -> 验证双引导弹窗与跳转 -> 补授权验证免重启即时生效与拓扑更新）。

### 剩余工作（更新）

- 第 6 节取向一（权限缺失时的行为）已由双权限门控天然实现为「不齐备不落锁 + 引导」；HID 异常时通过 `evidence-unavailable` 降级磁贴提示。
- 媒体键静默反馈（第 6 节第二条）与「长按 Ctrl」归属（第 8 节）按需待产品确认。
- 需由下一位接手开发者按第 7 节验收项在实机上运行测试版 App 进行端到端复验。

## 1. 问题现象（用户报告与复现）

运行实例：`/Applications/HagimiMonitor.app`（可执行名 `HagimiMonitorDirect`，Direct 渠道，Developer ID 签名 + 公证，v1.6.0，Team VTQ6S5M4K3）。环境：macOS 27 / Apple Silicon 笔记本；外接罗技 MX Keys Mini B（蓝牙）与 VXE R1 鼠标；设置 `keyboardLockBlocksExternal=0`（仅锁定内置）、自动解锁 20 分钟、媒体键接管开启且 `showOSD=0`。

1. 外接键盘从未出现在设置页：键盘锁卡片展开后小字恒为「未检测到外接键盘」（该分支含义 = 内置键盘已识别、外接列表为空）。
2. 开启键盘锁（仅内置）后，内置键盘「大部分按键仍可输入」，只有音量/亮度等 F 键被吞掉（无任何反馈）。
3. 后续实验发现：同设置下在外接键盘（MX Keys）上打字也无任何输出——即「仅锁定内置」在缺权限组合下退化为全拦。
4. 用户手动给应用补授系统「输入监控」权限后：内置键盘立即能被完整拦截（无需改代码）。

## 2. 结论（根因）

**根因 A：键盘锁只检测/申请「辅助功能」，权限模型不完整。**
- 门控代码只有 `AccessibilityPermissionService`（`AXIsProcessTrusted()`），见 `HagimiMonitor/QuickToolsStore.swift:84`（`keyboardLockPermission`）与 `toggleKeyboardLock()` 的 `isTrusted` 判断（约 :202）。
- Release 二进制中不存在任何输入监控 API 引用（`nm -u` / `strings` 均无 `CGRequestListenEventAccess`、`CGPreflightListenEventAccess`、`IOHIDCheckAccess`、`IOHIDRequestAccess`）——从未检测过该权限。
- 历史原因：提交 **e085ae94（2026-09-17「双渠道权限统一」）** 删除了 `HagimiMonitor/InputMonitoringPermissionService.swift`（-68 行），把 App Store 渠道原有的输入监控审批流统一改为辅助功能，提交说明为「App Store 渠道废弃无效的输入监控通道」。对媒体键类系统事件（NX_SYSDEFINED）成立，对键盘锁不成立。
- 实测行为（仅辅助功能）：事件 tap 能创建、能收到并吞掉 `systemDefined`（音量/亮度失效、无反馈），但**收不到键盘按键事件**（keyDown/keyUp/flagsChanged）→ 字母与修饰键全部穿透；同时 HID 输入值不可读（见根因 B）→ 证据链为空 → tap 把唯一看得见的 systemDefined 按默认「内置」吞掉。这正是现象 2 的完整解释。

**根因 B：macOS 27 键盘类 HID 设备为 TCC 受限设备，代码忽略打开失败（静默 HID 盲区）。**
- IORegistry 实证：MX Keys、VXE 鼠标、内置键盘的键盘 collection 均带 **`RequiresTCCAuthorization = Yes`**；无输入监控的进程打开这些设备会失败。
- `KeyboardLockController.setupHIDMonitoring()`（`HagimiMonitor/KeyboardLockController.swift:293-307`）调用 `IOHIDManagerOpen` 时**不检查返回值**，失败既不报错也不重试：
  - `scanKeyboardTopology()`（同文件 :341-362）拿不到受限设备 → 设置页「未检测到外接键盘」（现象 1）；
  - 锁内的 HID 证据链为空 → 所有事件判「内置」（默认兜底）→ 「仅锁定内置」时外接键盘也被拦（现象 3）。
- 对比实证：终端进程持有输入监控（`CGPreflightListenEventAccess() == true`）时，同样的扫描/探针可完整枚举并正确分类 MX Keys（`外接键盘`）——分类算法本身无问题。

**根因 C：授权/启动时序——已失败的 HID 监听不会重建。**
- HID manager 在 `start()` 落锁时一次性打开（`setupHIDMonitoring`，仅 `stop/teardown` 或范围热切换时才拆装）；补授权限后不重建。tap 的事件投递按 TCC 实时判定（所以用户看到「补授权后按键立刻能拦」），但 HID 打开已失败不会自动重试。
- 用户实测：**完全退出并重启应用后**，设置页列出 MX Keys、仅内置锁定下内置被拦、MX Keys 正常打字——三项全部恢复。即代码逻辑在权限齐备且时序正确时是可用的，问题集中在权限门控、静默失败与体验。

**根因 D：全程无用户可见提示，静默失效。** 权限不完整、设备打开失败、证据链为空均无提示（`keyboardLockPermissionHint` 只覆盖「完全未授权该渠道权限」一种情况）。

## 3. 排查过程与关键证据

按时间顺序，全部在本机复现：

1. **干净进程扫描**（终端）：复刻 `scanKeyboardTopology` 的匹配与 `classify` 判定，枚举到 3 个键盘设备——内部键盘 `内置`、MX Keys Mini B `外接键盘`、VXE 鼠标 `被排除(指向设备)`。结论：分类算法无误，问题在应用进程上下文。
2. **观察模式现场探针**（`tmp/hid-scan/listen.swift`）：原样复刻 `KeyboardEventAttribution` 与 HID/CG 事件通道，只观察不吞事件。两轮共 150 秒零事件（连鼠标事件都没有）；同时验证终端进程持有 `CGPreflightListenEventAccess = true`、`CGPreflightPostEventAccess = true`——探针工具链正常，零事件是因为用户当时不在机器前，不是权限问题。
3. **运行实例取证**：`strings`/`nm` 确认 /Applications 里的可执行文件包含当前键盘锁逻辑与本地化键；进程启动时间（17:04）早于用户补授输入监控的时间——为根因 C 提供了时序基础。
4. **用户现场对照实验（关键）**：
   - 补授权前：字母与 Control/Option/Command 均可输入；音量/亮度被吞。
   - 补授权后：按键立刻被完整拦截（未改任何代码）。
   - 关闭键盘锁：音量等立即恢复 → 证明媒体键是被「键盘锁」吞掉，而非「媒体键接管」（后者在锁定期被设计性停用，`HagimiMonitorDirectOnly/MediaKeyController.swift:35`）。
   - 重启应用后：设置页列出 MX Keys、内置被拦、MX Keys 正常打字（现象 1/3 全部消失）。
5. **IORegistry 取证**（`ioreg -l -w0 -r -c IOHIDDevice`，解析各设备子树的 `IOUserClientCreator`）：
   - 键盘类设备带 `RequiresTCCAuthorization = Yes`（BLE 键盘/鼠标、内置键盘的键盘 collection；内置键盘另有多个无标记 collection）。
   - macOS 27 上 BLE 键盘以 `IOHIDUserDevice` 形态出现（`Transport = "Bluetooth Low Energy"`），属正常表现。
   - 故障期间应用进程**不持有任何 HID 客户端**（manager 未成功打开任何设备），而同设备上 WindowServer、微信输入法 WeType（MX Keys/内置）、Mac Mouse Fix Helper（VXE）均有客户端——证明设备本身可被授权进程打开。
6. **代码审查**：`KeyboardLockController.swift` 顶部注释（约 :158-161）「Direct 凭辅助功能权限创建 tap；App Store 沙盒内凭输入监控权限创建」在 e085ae94 后已与实现不符，需更新。归因状态机本身完整（含时间窗、按键级记账、兜底策略），单测（`HagimiMonitorTests/KeyboardLockControllerTests.swift`）只覆盖合成时间戳的归因逻辑，未覆盖「设备打开失败/权限缺失」路径。
7. **媒体键还原链**：锁定期 `MediaKeyController` 主动停用 tap（防止 headInsert 抢在锁 tap 之前）；音量/亮度由锁的 `systemDefined` 分支静默吞掉（`settings.mediaKey.showOSD=0`，无 OSD 反馈）——即「媒体键失效」在权限齐备时也是预期行为，但反馈缺失易被误读为故障。

## 4. 关键代码位置清单

| 位置 | 内容 |
| --- | --- |
| `HagimiMonitor/QuickToolsStore.swift:84`、`:202`、`:154-181` | 权限门控（仅辅助功能）、落锁判断、权限联动 |
| `HagimiMonitor/AccessibilityPermissionService.swift` | 辅助功能服务：`isTrusted`/`refresh`/`request`/轮询/系统设置跳转，可作为新服务的形态参考 |
| `HagimiMonitor/KeyboardLockController.swift:293-307` | `setupHIDMonitoring`：`IOHIDManagerOpen` 返回值被忽略 |
| `HagimiMonitor/KeyboardLockController.swift:341-362`、`:372-386` | `scanKeyboardTopology` / `classify` |
| `HagimiMonitor/KeyboardLockController.swift:445-462`、`:429-442` | `isBuiltInKeyboard` / `isExternalKeyboard`（判定逻辑本身验证无误） |
| `HagimiMonitor/KeyboardLockController.swift:158-161` | 已过时的渠道权限注释 |
| `HagimiMonitorDirectOnly/MediaKeyController.swift:35` | 锁定期停用媒体键 tap |
| `HagimiMonitor/Localizable.xcstrings` | `quicktools.permission.input-monitoring`（「需要"输入监控"授权」）已存在但当前无代码引用，可复用 |
| 提交 `e085ae94` | 删除 `InputMonitoringPermissionService.swift`（原 App Store 渠道实现可 `git show e085ae94^:HagimiMonitor/InputMonitoringPermissionService.swift` 找回） |
| `HagimiMonitor/HagimiMonitor.entitlements` | App Store 渠道 entitlements（e085ae94 曾追加 USB HID 权限，接手时核对） |

## 5. 修复方案（本节为当时建议的方案原文，实施情况与偏差见第 0 节）

1. **恢复输入监控权限服务并接入双渠道门控**
   - 新增/恢复权限服务（形态参考 `AccessibilityPermissionService`：`ObservableObject`、`@Published isTrusted`、`refresh`/`request`、授权轮询上限、跳转 `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`）。
   - 检测 API：`CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`（或等价的 `IOHIDCheckAccess` / `IOHIDRequestAccess`）。
   - 门控模型：Direct = 辅助功能（建 tap）+ 输入监控（打开 TCC 受限设备、接收键盘事件与 HID 输入值）；App Store = 输入监控（沙盒内原设计；辅助功能在沙盒下的实际可用性需实测核对）。渠道差异用既有编译条件（`DIRECT_DISTRIBUTION`）处理，避免向用户暴露内部术语。
   - 落锁前要求所需权限齐备；权限被撤销时立即 stop（现有 `observeKeyboardLockPermission` 模式扩展到双权限）。
   - 提示文案复用 `quicktools.permission.input-monitoring`，按渠道给出对应权限名。
2. **HID 监听健壮性**
   - `setupHIDMonitoring` 检查 `IOHIDManagerOpen` 返回值；打开后校验实际拿到的设备数（可用 `IOHIDManagerCopyDevices` 与匹配结果对比），失败时记录可诊断状态（供 UI/日志使用）。
   - 权限状态由未授权变为已授权时：若已锁定或挂起，**自动重建 HID 监听**（teardown + setup，走主线程），使用户无需重启应用（根因 C）。
   - 保留现有 reset 语义（重建时清空归因证据）。
3. **失败可见性（取向待拍板，见第 6 节）**
   - 权限不齐/证据链不可用时不进入「已锁定」的假象，或在磁贴/设置页给出醒目提示。
4. **注释、测试与文档**
   - 更新两处过时注释（`KeyboardLockController` 顶部、`QuickToolsStore` 顶部渠道权限说明）。
   - 补测试：把 HID manager 的创建/打开抽一层可注入的边界，覆盖「打开失败不静默」「权限变化触发重建」；归因测试保持不动。
   - README / RELEASE_NOTES 按发布节奏补充修复条目。

## 6. 待拍板的产品取向

- **权限缺失时的行为**：取向 A = 保持拦截 + 醒目提示（安全，但缺权限时「仅内置」会退化为全拦）；取向 B = 放行 + 提示（不会锁死，但「锁」可能悄悄失效）。建议方案 1/2 完成后再定：权限齐备是常态后，缺权限时优先「明确提示不进入锁定」。
- **锁定期媒体键的反馈**：当前完全静默（OSD 关闭 + tap 吞掉）。是否需要替代反馈（如磁贴提示）由产品决定。
- **App Store 渠道**：确认沙盒下输入监控审批流恢复后的引导文案与授权路径。

## 7. 验收标准

- 构建：`HagimiMonitor`（App Store）与 `HagimiMonitorDirect` 两个 scheme 均通过；Direct 测试套件绿（`xcodebuild ... -scheme HagimiMonitorDirect ... test`，见 AGENTS.md）。
- 实机（Direct，权限齐全）：设置页列出 MX Keys Mini B；「仅内置」锁定下内置被拦、MX Keys 可正常打字；「全部拦截」下两者全拦；媒体键被吞（预期）；外接键盘拔出自动解锁链路正常。
- 时序：补授权限后**无需重启应用**即可生效（重建监听）。
- 提示：缺少输入监控时不出现「看起来已锁定但实际拦不住/乱拦」的静默状态。
- 回归：App Store 渠道可按新流程完成授权引导（沙盒实机验证）。

## 8. 遗留与未决

1. **「长按 Ctrl 热键」归属未确认**（微信输入法语音键？系统听写？）。若其触发监听位于事件 tap 之外（系统/输入法层），tap 方案无法拦截，属能力边界；需用户确认具体功能后单独验证。
2. 第三方 HID 读取者（微信输入法 WeType、Mac Mouse Fix Helper）在本次故障中非变量，但属排查疑难时的环境因素。
3. 用户在轨的细节：媒体键接管开着（亮度+音量）且 OSD 关闭；`settings.quickTools.keyboardLockScope`（旧键值 = all）是无消费方的历史遗留值，当前以 `keyboardLockBlocksExternal` 为准。

## 9. 诊断工具与命令（`tmp/hid-scan/`，gitignore，不提交）

- `main.swift`：一次性扫描，复刻 `scanKeyboardTopology`/`classify`/`isBuiltInKeyboard`/`isPointingDevice`，打印各设备的 transport、Built-In 属性、用途对、元素统计与分类。运行：`swift tmp/hid-scan/main.swift`。
- `listen.swift`：观察模式现场探针（不吞事件），复刻归因器，打印 HID 上报与 CG 决策及时间窗证据，15 秒心跳。编译运行：`swiftc -O tmp/hid-scan/listen.swift -o tmp/hid-scan/listen && ./tmp/hid-scan/listen 90`（日志同时写 stdout 与 `tmp/hid-scan/listen.log`）。
- `tcc-check.swift`：`CGPreflightListenEventAccess()` / `CGPreflightPostEventAccess()`。
- IORegistry 检查：`ioreg -l -w0 -r -c IOHIDDevice`，重点看各设备子树的 `RequiresTCCAuthorization`、`HIDVirtualDevice` 与 `IOUserClientCreator`（哪个 pid 打开了哪个键盘）。
- 应用侧：`nm -u` / `strings /Applications/HagimiMonitor.app/Contents/MacOS/HagimiMonitorDirect`；`defaults read com.acerola.hagimi-monitor.direct`。

## 10. 交接备注

- 本修复涉及权限模型变更与用户可见行为，实施前先与用户确认第 6 节取向再动代码（项目协作约定：先确认后实施）。
- 已验证可用现状（重启后一次通过）：分类判定、归因状态机、外接断开自动解锁、媒体键联动均正常；缺的只是权限门控、失败处理与反馈。
