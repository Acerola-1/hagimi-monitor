## Context

本变更在已有 SMC 基础设施(`SMCReader` 已能读 CPU 温度)上扩展风扇指标。设计参考开源实现 exelban/Stats(已 clone 到 `/tmp/stats` 临时分析,SMC 路径与本文一致),重点是**机型适配**与**多风扇处理**。

## 关键设计点

### 1. 为什么 `userSelectableCases` 必须改函数

当前实现是 `static let` —— 编译时确定,与运行时硬件状态完全脱钩。要让"无风扇机不出现风扇选项"成立,必须让该函数在调用时拿到 `fanAvailable` 上下文。

```swift
// 当前(静态)
static let userSelectableCases: [MenuBarMetricKind] = {
    #if DISPLAY_CONTROL
    return allCases
    #else
    return allCases.filter { $0 != .cpuTemperature }
    #endif
}()

// 改后(运行时)
static func userSelectableCases(hasFan: Bool) -> [MenuBarMetricKind] {
    var cases: [MenuBarMetricKind] = allCases
    #if !DISPLAY_CONTROL
    cases.removeAll { $0 == .cpuTemperature }
    #endif
    if !hasFan {
        cases.removeAll { $0 == .fanSpeed }
    }
    return cases
}
```

**调用点影响**:全局检索约 2-3 处(`MenuBarStatusLabel` 初始默认集合 + `GeneralSettingsView` Picker)。改 `static let` 改 `static func` 是本次变更对架构的**唯一结构性变化**,其余都是加 case / 加视图,影响面可控。

### 2. 风扇数检测时机:`FNum` 启动时读一次

`FNum` 是 SMC 静态 key,不会动态变化(风扇数 = 机器物理属性)。所以:
- 启动时读一次,缓存到 `FanSampler.available`
- 后续采样**不重复读** FNum,只读 `F0Ac`/`F1Ac`/...
- 若启动时 `FNum` 返回 nil(无风扇 / 读取失败),`available = false`,UI 全部隐藏

`available` 在 `MonitorStore` 暴露为 `var fanAvailable: Bool { !fans.isEmpty }`,所有 UI 订阅这一个布尔。

### 3. 多风扇取 max,而不是 average 或 list

- **max** 反映"最热的那个",对应"系统散热压力峰值"——和"温度"语义对齐
- **average** 隐藏极端值,失去监控意义
- **list**(每风扇独立 cell)与单 kind 设计冲突,会让 `MenuBarMetricKind` 变成可变的 N 个 case
- Mac Pro 8 风扇的 max RPM = "系统当前最紧的风扇",够用

如果未来需要"看具体哪个风扇",通过面板展开区 `FanList` 提供(不影响菜单栏)。

### 4. SMC 读取的失败处理

SMC 读 key 失败的可能原因:
- 风扇**当前确实没在转**(0 RPM,合法值,`F0Ac` 返回 0)
- SMC key **不存在**(老款 Mac 可能 key 命名差异,如 `F0Ac` vs `F0ID` 之类)
- 权限被拒(sandbox 路径在 macOS 13+ 已通,但极端配置可能挂)

处理:
- `FNum` 读失败 → 视为无风扇
- `F0Ac`...循环中**任一失败跳过**,不抛错;若全部 0 或全失败,`maxFanRPM()` 返回 nil
- 用户 UI 看到 nil 时:菜单栏显示占位 `unavailable`,面板不显示该行(避免空白行)

### 5. 菜单栏 4 字符格式 `1200`(无单位)

- 风扇 RPM 典型范围:0-5000(笔记本)到 0-8000(Mac Pro 高负载)
- 4 字符刚好覆盖 0-9999,`"1200"` / `"4500"` / `" 800"`(右对齐 0)
- 9999 作 cap,超此值罕见(Mac Pro 极限散热也很少破 8000)
- **不带单位**:参考 Stats 菜单栏(`1200` 无单位),单位信息靠 tooltip/hover 提示
- 视觉一致性:与现有 icon/text 模式"4 字符定宽"无缝衔接,无需改 `MenuBarStatusLabel` 的预留逻辑

### 6. 面板行位置:GPU 和内存之间

按模块语义分组:
- CPU(计算) → GPU(计算) → **Fan(散热响应)** → Memory(资源) → Storage / Network / Battery / Power

"Fan 紧跟 GPU"反映"GPU 渲染压力 → 风扇响应"的反馈链,与"CPU → 温度 → 风扇"的逻辑也兼容(GPU 单元的下方就是风扇,便于交叉查看)。

### 7. 面板展开样式:固定 5 行占位

`FanList` 沿用 `InlineDiskProcessList` 的"固定 5 行位置"模式:
- `fans.count` < 5 时:前 N 行显示真实风扇,后 5-N 行显示 "—" 占位
- `fans.count` >= 5 时:仅显示前 5 个(Mac Pro 8 风扇看 5 个也够;剩余的极端情况用 tooltip/详情)

**为什么不按真实数量展开**:面板布局稳定性 > 信息完整性,5 行固定位置避免展开/收起时的二次跳变(与 `InlineDiskProcessList` 注释里写的设计目标一致)。

### 8. 降级行为:已选 `fanSpeed` 但机器无风扇

用户已选 `fanSpeed` 指标(假设有风扇机),之后**降级到无风扇场景**:
- 设置里 `fanSpeed` 选项**消失**(因为 `userSelectableCases` 不再含它)
- 但用户的 `menuBarMetricKinds: [MenuBarMetricKind]` 仍保留 `.fanSpeed`(不自动移除)
- 菜单栏渲染 `.fanSpeed` 时,值 = nil → formatter 返回 `unavailable` → 显示占位
- 面板不渲染风扇行(`fanAvailable = false`)

这是**软降级**:用户的数据不丢,只是显示空。等用户切回有风扇机,自动恢复。

## 风险与协调

- **架构改动面**:`userSelectableCases` 改函数 → 全局 2-3 处调用点需传 `hasFan`。改前先 grep 检索全部调用,确保不漏。详见 tasks 2.5。
- **SMC entitlement**:你已有 CPU 温度走通,风扇同源,基本无新风险。`docs/macos27.txt` 提到 Apple Silicon 的 `AppleSMC` IOService 接口在 sandbox 下仍可读。
- **多风扇测试**:Mac Pro / Studio 需要借机实测一次,验证 max RPM 正确性。日常开发可在 MacBook Pro(2 风扇)上跑通。
- **预留宽度**:`"9999"` 4 字符 max,极端情况(>9999 RPM)会 cap 到 9999 显示。Mac Pro 实测 idle 约 800-1200 RPM,负载下 3000-5000,几乎不触发 cap。
- **与 P0/P1/P2 关系**:P0 已 commit(bdd96faa),P1/F7 测量缓存可顺带应用在新指标(若时机合适);P2 不冲突。
- **不做的事**:
  - 不支持风扇**控制**(只读 RPM,不调速)——与 Stats 的 `setFanSpeed` 保持距离
  - 不做风扇**健康检测**(异常 RPM 报警)——超出本变更范围
  - 不做风扇**温度曲线联动**(风扇 RPM 随温度的历史曲线)——sparkline 已有但只画 RPM 自身
