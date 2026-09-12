# 硬件数据来源与字段映射（HARDWARE-DATA-MAP）

这份文档回答一个问题：**每个模块右栏、以及「本机」每个分类里的每一条，从哪来、我们是否已经能读到、要不要保留。**

调查对象：`tmp/ref-mac-perf`（Zesty0wl/mac-performance-monitor）。
产出：给实现阶段直接用——字段 → 确切接口/键 → 我们现状 → 决策。

**「我们现状」三档标记**

| 标记 | 含义 |
| --- | --- |
| ✅ 已有 | 本项目已在读，见 `HagimiMonitor/Samplers/` 与 `Localizable.xcstrings` 的 `metric.*` |
| 🆕 需新读 | 现在没有，需要新增读取（接口已确认可行） |
| ⛔ 不可得 | 公开 API 拿不到，或需要 root/特权组件——**不伪造数值**，按缺失显示 |

---

## 1. 三条关键结论

**① 参考项目的静态规格集中在硬件页，不在监控页。**
它的监控页右侧轨（`MainRailLayout` 的 300pt 轨）装的是**实时读数与 Top 榜单**：Dashboard 轨 = 核心网格 / 内存构成 / Swap / 热学（Live CPU / Live GPU / Live fans / thermal state）/ Top CPU·磁盘进程；GPU 轨 = Device（芯片/核数/显存/温度/风扇/热限/功耗帽）/ By category / AI workloads；磁盘轨 = Health（NVMe SMART）/ Free space / Top disk processes；电池轨 = Battery health / Electrical / Adapter & power mode。
而**静态规格**（机型、芯片、各级缓存、Metal 能力、显示器参数、磁盘 SMART 能力…）全在硬件页的对应 section 里。

所以我们的右栏两组，来源分工是固定的：

| 我们右栏的组 | 来源 |
| --- | --- |
| 静态规格组 | 参考项目**硬件页**的对应 section |
| 运行状态组（实时） | 参考项目**监控页**右轨的实时读数 |

**② 运行状态组优先复用我们已有的 `metric.*`，不照搬它的读数。**
我们已经在读的东西比想象中多：CPU 的 user/system/idle 拆分与热压力、GPU 的时钟态/显存/温度/功耗帽/渲染器·分块器、内存的压缩/交换/压力/带宽、磁盘的 SMART/可用空间、网络 IPv4/IPv6/RSSI/SSID、电池的循环/健康/电压/电流/温度/功耗/适配器 PD 档位。
照搬它的读数只会把已有能力重做一遍。

**③ 有一项它没做、我们也不该做：CPU 主频。**
Apple Silicon 没有公开的当前 CPU 频率接口（`powermetrics` 需 root）。参考项目全仓库没有 CPU 频率；我们的 `Samplers/` 里也搜不到。
原型夹具里我原先写的「主频 1 512 MHz」是**编的**，已换成「空闲占比」（`metric.cpu.idle`，✅ 已有）。

---

## 2. 数据源总表

### 2.1 system_profiler（主力，16 个 DataType 要读）

调用方式：`/usr/sbin/system_profiler -json -timeout 25 <DataType>`，**每个 DataType 一个进程、并发上限 6**。
参考项目是**一次性 `capture`，只在打开或手动 Refresh(⌘R) 时跑**，不跟采样 tick——它的注释写得很直白：*"Nothing here runs on a timer: the explorer refreshes only when asked."*
本项目已有同模式的先例（`StorageSMARTProbe` 读 `SPNVMeDataType`、`BluetoothBatterySampler` 读 `SPBluetoothDataType`），**必须沿用「一次性读 + 长缓存 + 手动刷新」**。

| DataType | 供给我们的分类 | 我们现状 |
| --- | --- | --- |
| `SPHardwareDataType` | 本机 | 🆕 |
| `SPMemoryDataType` | 内存 | 🆕 |
| `SPDisplaysDataType` | 显示器（也是 GPU 核数/Metal 的第二来源） | 🆕 |
| `SPStorageDataType` | 磁盘（卷） | 🆕 |
| `SPNVMeDataType` | 磁盘（物理盘） | ✅ 已有（`StorageSMARTProbe`） |
| `SPSerialATADataType` | 磁盘（SATA 机型/外接盘） | 🆕 |
| `SPNetworkVolumeDataType` | 磁盘（网络卷） | 🆕 |
| `SPPowerDataType` | 电源与电池 | 🆕 |
| `SPNetworkDataType` | 连接（接口/IP/DNS） | 🆕 |
| `SPEthernetDataType` | 连接（有线接口规格） | 🆕 |
| `SPBluetoothDataType` | 连接（蓝牙） | ✅ 已有（`BluetoothBatterySampler`，但它只取设备电量） |
| `SPUSBHostDataType`（空则回退 `SPUSBDataType`） | 连接（USB） | 🆕 |
| `SPThunderboltDataType` | 连接（雷雳/USB4） | 🆕 |
| `SPiBridgeDataType` | 系统与安全 | 🆕 |
| `SPSecureElementDataType` | 系统与安全（安全隔区） | 🆕 |
| `SPSoftwareDataType` | 系统与安全 | 🆕 |

**不读**（参考项目有、我们砍掉）：`SPAudioDataType`、`SPCameraDataType`、`SPPCIDataType`、`SPSPIDataType`、`SPCardReaderDataType`、`SPSmartCardsDataType`、`SPPrintersDataType`。

**遍历规则**（要照做，否则会丢字段）：

- `_name` → 节点标题；`_items` / 数组 of record → 子节点（一台显示器、一个卷、一个 USB 设备各成一个子节点）
- 字典值（如 `physical_drive`）→ 作为**分组**展开，组名取该键的标签
- 空值（nil / 空白串 / 空数组）→ 不生成属性行
- 结构键 `_name` / `_items` / `_properties` 不显示

**值格式化**（按 key 后缀，参考项目 `HardwareLabel.value` 的规则）：

| key 条件 | 输出 |
| --- | --- |
| 以 `_in_bytes` / `bytes` 结尾 | 人类可读字节 + 括号内原始分组字节 |
| 以 `srate` / `sample_rate` 结尾 | `n,000 Hz` |
| 以 `watts` 结尾 | `n W` |
| 含 `timer` | `0` → 「从不」，否则 `n 分钟` |
| 含 `percent` / `state_of_charge` | `n%` |
| 以 `_duration` 结尾 | `n 秒` |
| 整数且 ≥ 10000 | 千分位分组 |
| 其它 | 原样 |

**注意**：参考项目的**值永不翻译**（中文界面下也显示 `Yes` / `Built-in` / `Supported`）。我们应当反过来——枚举值走 `Localizable.xcstrings`，这是与我们既有做法一致的改进。

### 2.2 sysctl（原生读取器的确切键）

| 用途 | 键 | 我们现状 |
| --- | --- | --- |
| 机型标识 | `hw.model` | ✅ 已有（`StatisticsReportBuilder.modelName()`） |
| 芯片名 | `machdep.cpu.brand_string` | ✅ 已有（`UsageReporter.chipName()`） |
| 架构 | `hw.machine` | 🆕 |
| CPU 核数 | `hw.physicalcpu` / `hw.logicalcpu` | 🆕 |
| 性能核/能效核簇数 | `hw.nperflevels` | 🆕 |
| 每簇 | `hw.perflevel{n}.name` / `.physicalcpu` / `.physicalcpu_max` / `.l1icachesize` / `.l1dcachesize` / `.l2cachesize` / `.cpusperl2` | 🆕 |
| 缓存行 / 页大小 | `hw.cachelinesize` / `hw.pagesize` | 🆕 |
| 时基频率 | `hw.tbfrequency` | 🆕 |
| CPU 家族 / 子家族 | `hw.cpufamily` / `hw.cpusubfamily` | 🆕 |
| 目标类型 | `hw.targettype` | 🆕 |
| 64 位能力 | `hw.cpu64bit_capable` | 🆕 |
| 虚拟化支持 | `kern.hv_support` | 🆕 |
| 指令集特性 | 遍历 `hw.optional.*`（只取值为 0/1 的；`hw.optional.arm.*` 去前缀） | 🆕 |
| 内存容量 | `hw.memsize` / `hw.memsize_usable` | 🆕 |
| ECC | `hw.optional.ecc` | 🆕 |
| 系统版本 | `kern.osproductversion` / `kern.osversion`（build） | 🆕 |
| Darwin 版本 | `kern.osrelease` | 🆕 |
| 内核 | `kern.version` / `kern.ostype` | 🆕 |
| 主机名 | `kern.hostname` | 🆕 |
| 上次启动 | `kern.boottime` | 🆕 |
| 启动参数 | `kern.bootargs` | 🆕 |
| 安全模式 / 安全内核 | `kern.safeboot` / `kern.secure_kernel` | 🆕 |
| 最大进程数 / 打开文件数 | `kern.maxproc` / `kern.maxfiles` | 🆕 |

### 2.3 IOKit

| 用途 | 节点 | 我们现状 |
| --- | --- | --- |
| 产品名 / SoC / 内存可升级 / 显示器镜像 / Wi-Fi 芯片 / 蓝牙 LE Audio | `IODeviceTree:/product` | 🆕 |
| 机型标识 / 型号编号 / 序列号 / 硬件 UUID / 监管型号 / 地区 / 原产地 / 制造商 / 设备树 / 固件版本 / 参考时钟 | `IOServiceMatching("IOPlatformExpertDevice")` | 🆕 |
| GPU 能力（Metal 特性全表） | `IOServiceMatching("AGXAccelerator")` + `MTLCreateSystemDefaultDevice()` | 🆕 |
| 神经网络引擎核数 | `IODeviceTree:/arm-io/ane` | 🆕 |
| 电池（循环/健康/容量/电压/电流/温度/序列号/电芯电压/适配器） | `AppleSmartBattery` | ✅ 已有（`BatterySampler`） |

### 2.4 SMC（只读，仅温度与风扇）

| 用途 | 读法 | 我们现状 |
| --- | --- | --- |
| 温度 | 枚举 `#KEY`，取 4 字符且以 `T` 开头的键，解码 `flt `/`ioft`/`ui16`/`ui8 `，门限 1–130 °C | ✅ 已有（`FanSampler` + 热压力采样） |
| 风扇 | `F0Ac`（转速）/ `F0Mx`（上限）/ `FNum`（数量） | ✅ 已有（`FanSampler`） |

**域分组**（按前缀）：`Tp`→CPU 性能核 die、`Te`→CPU 能效核 die、`Tg`→GPU 集群、`TH0`→SSD、`TB`→电池、`Ta`→气流（排除 `Ta0`）、`Ts`/`Th`→机身与主板、`TW`→无线、`TV`→电压轨、其余→其他。
**注意**：电池电压/电流走 IOKit，CPU/GPU 功耗走 IOReport——**都不在 SMC 传感器路径里**，所以传感器页只有温度与转速是对的。

### 2.5 CoreWLAN / Metal / ProcessInfo

| 用途 | 接口 | 我们现状 |
| --- | --- | --- |
| Wi-Fi：SSID / RSSI | `CWWiFiClient.shared().interface()` | ✅ 已有（`WiFiProbe`） |
| Wi-Fi：BSSID / 信道 / 频段 / PHY 模式 / 传输速率 / 噪声 / 安全 / 国家码 | 同一个 `CWInterface`，`bssid()` / `wlanChannel()` / `phyMode()` / `transmitRate()` / `noiseMeasurement()` / `security()` / `countryCode()` | 🆕 |
| Metal 能力 | `MTLCreateSystemDefaultDevice()` | 🆕 |
| 活动处理器数 | `ProcessInfo.activeProcessorCount` | 🆕 |
| Rosetta 2 | `/Library/Apple/usr/share/rosetta/rosetta` 是否存在 | 🆕 |

---

## 3. 六个监控模块的右栏映射

### 3.1 CPU

**参考项目在哪有 CPU 规格**：硬件页 Processor section（含 P/E 簇子树 + 指令集特性）。
**参考项目监控页右轨的 CPU 相关实时项**：`Live CPU`（die 温度）、`Live fans`、`Live thermal state`、`Top CPU processes`、核心网格。

| 我们右栏字段 | 来源 | 我们现状 | 决策 |
| --- | --- | --- | --- |
| 芯片 | `machdep.cpu.brand_string` | ✅ | 取 |
| 架构 | `hw.machine` | 🆕 | 取 |
| 物理核心 / 逻辑核心 | `hw.physicalcpu` / `hw.logicalcpu` | 🆕 | 取 |
| 性能核 · 能效核 | 遍历 `hw.perflevel{n}` 取各簇 `physicalcpu` | 🆕 | 取（合成一行） |
| 一级指令 / 数据缓存 | `hw.perflevel{n}.l1icachesize` / `l1dcachesize` | 🆕 | 取（P/E 两值合一格） |
| 二级缓存 | `hw.perflevel{n}.l2cachesize` | 🆕 | 取 |
| 缓存行 / 页大小 | `hw.cachelinesize` / `hw.pagesize` | 🆕 | 取 |
| 时基频率 | `hw.tbfrequency` | 🆕 | 取 |
| CPU 家族 | `hw.cpufamily`（十六进制） | 🆕 | 取 |
| 64 位能力 / 虚拟机支持 | `hw.cpu64bit_capable` / `kern.hv_support` | 🆕 | 取（布尔合并成一行两值或两行） |
| 目标类型 / 子家族 | `hw.targettype` / `hw.cpusubfamily` | 🆕 | **舍**（对用户无意义） |
| 指令集特性 | 遍历 `hw.optional.*`，参考项目列 60+ 项 | 🆕 | **砍成一行**：只列「部分支持」的几个 + 其余折叠，不铺满一栏 |
| 热压力 | `kern.memorystatus_vm_pressure_level` 同理的热压力采样 | ✅ `metric.cpu.thermal-pressure` | 取（运行状态） |
| 进程数 | 采样器进程表 | ✅ `metric.cpu.process-count` | 取（运行状态） |
| 开机时长 | `kern.boottime` | ✅ `metric.cpu.uptime` | 取（运行状态） |
| 空闲占比 | 采样器 | ✅ `metric.cpu.idle` | 取（运行状态） |
| ~~主频~~ | — | ⛔ | **删**（Apple Silicon 无公开接口） |
| 用户 / 系统占比 | 采样器 | ✅ `metric.cpu.user` / `.system` | 备选（右栏放不下时与空闲占比二选一） |
| 核心占用拆分（P/E 汇总） | 采样器 | ✅ `metric.cpu.core-split` | 已在主列图表，右栏不重复 |

### 3.2 GPU

**参考项目在哪有 GPU 规格**：硬件页 Graphics section（Metal 能力全表）+ 监控页 GPU 轨的 Device 卡。

| 我们右栏字段 | 来源 | 我们现状 | 决策 |
| --- | --- | --- | --- |
| 图形处理器 | `MTLCreateSystemDefaultDevice().name` | 🆕 | 取（Apple Silicon 上即芯片名） |
| GPU 核心 | `SPDisplaysDataType.sppci_cores` 或 `IODeviceTree:/product` | 🆕 | 取 |
| 架构 | `MTLDevice.architecture.name` | 🆕 | 取 |
| Metal 支持 | `SPDisplaysDataType.spdisplays_mtlgpufamilysupport` | 🆕 | 取 |
| GPU 家族 | `MTLDevice` | 🆕 | **舍**（与架构重复） |
| 统一内存 | `MTLDevice.hasUnifiedMemory` | 🆕 | 取（可并进内存分类，避免两处重复） |
| 推荐工作集 / 最大缓冲长度 | `recommendedMaxWorkingSetSize` / `maxBufferLength` | 🆕 | 取 |
| 最大线程组内存 / 线程数 | `threadgroupMemoryLength` / `maxThreadsPerThreadgroup` | 🆕 | **只取线程组内存** |
| 光线追踪 / 32 位 MSAA / BC 纹理压缩 / 读写纹理 | `MTLDevice.supports*` | 🆕 | **精选这四项** |
| 32 位浮点过滤 / 动态库 / 函数指针 / LOD 查询 / 参数缓冲 / 渲染管线光线追踪 | `MTLDevice.supports*` | 🆕 | **舍**（纯 Metal 开发者向） |
| 稀疏图块大小 / 注册表 ID / 位置 / 低功耗 / 可拆卸 / 无头 / Metal 插件 / 驱动 | IOKit AGX + Metal | 🆕 | **舍**（对用户无意义；后四项在 Mac 上恒为否） |
| 神经网络引擎核心数 | `IODeviceTree:/arm-io/ane` | 🆕 | 取（只取核数） |
| ANE 类型 / 兼容 / 角色 / IOP 版本 | 同上 | 🆕 | **舍** |
| 显存占用 / 已分配 | 采样器 | ✅ `metric.gpu.gpu-memory` / `.allocated` | 运行状态 |
| 时钟态 | 采样器（IOReport dominant state + residency） | ✅ `metric.gpu.clock-state` | 运行状态 |
| 核心温度 | 采样器 | ✅ `metric.gpu.temperature` | 运行状态 |
| GPU 功耗 | 采样器 | ✅ `metric.battery.gpu-power` | 运行状态 |
| 渲染器 / 分块器 | 采样器 | ✅ `metric.gpu.render` / `.tiler` | 备选（右栏只留核心占用） |
| 热限 / 功耗帽 | 采样器 | ✅ `metric.gpu.throttle` / `.power-cap` | 取（比参考项目的 recoveries 有用） |
| GPU recoveries | — | 🆕 | **舍**（参考项目有，属故障计数） |

### 3.3 内存

**参考项目**：硬件页 Memory section（native 5 项 + `SPMemoryDataType` 8 项）。
注意 Apple Silicon 上 `dimm_*` 多数为空或 `Not Provided`，参考项目的 `memoryFacts` 也只是把 `dimm_type` + `dimm_manufacturer` 拼成一句话。

| 我们右栏字段 | 来源 | 我们现状 | 决策 |
| --- | --- | --- | --- |
| 总容量 | `hw.memsize` | ✅ `metric.memory.total` | 取 |
| 系统可用 | `hw.memsize_usable` | 🆕 | 取 |
| 内存类型 | `SPMemoryDataType.dimm_type` | 🆕 | 取；空则显示「统一内存」 |
| 页大小 | `hw.pagesize` | 🆕 | 取 |
| ECC | `hw.optional.ecc` | 🆕 | 取 |
| 内存带宽 | 采样器 | ✅ `metric.memory.memory-bandwidth` | 取 |
| 可升级 | `IODeviceTree:/product` | 🆕 | **舍**（Apple Silicon 恒为否） |
| 制造商 / 部件编号 / 序列号 / 频率 / 状态 | `SPMemoryDataType` | 🆕 | **全舍**（这本机基本为空） |
| 已用 / 压缩 / 交换 / 压力 | 采样器 | ✅ `metric.memory.used` / `.compressed` / `.swap-used` / `.pressure` | 运行状态 |

### 3.4 磁盘

**参考项目**：硬件页 Storage section（`SPStorageDataType` 卷 + `SPNVMeDataType`/`SPSerialATADataType` 物理盘 + `SPNetworkVolumeDataType`）+ 监控页 Health 卡的 NVMe SMART 全表。

| 我们右栏字段 | 来源 | 我们现状 | 决策 |
| --- | --- | --- | --- |
| 卷名 / BSD 名称 / 文件系统 / 挂载点 | `SPStorageDataType` | 🆕 | 取（多卷时每卷一组） |
| 容器容量 / 可用空间 | `size_in_bytes` / `free_space_in_bytes` | 🆕（`metric.storage.total`/`.free` 已有总量） | 取 |
| 可写 / 卷 UUID / 忽略所有权 | `SPStorageDataType` | 🆕 | 取可写与 UUID；**舍**忽略所有权 |
| 设备名 / 介质名称 / 介质类型 | `physical_drive` 或 `SPNVMeDataType` | 🆕 | 取媒体类型，介质名称舍（与设备名重复） |
| 协议 | `physical_drive.protocol` | 🆕 | 取 |
| SMART 状态 | `smart_status` | ✅ `metric.storage.smart` | 取 |
| TRIM 支持 | `SPNVMeDataType.spnvme_trim_support` | 🆕 | 取 |
| 型号 / 固件版本 / 序列号 / 分区表 | `device_model` / `device_revision` / `device_serial` / `partition_map_type` | 🆕 | 取型号与固件；**舍**序列号（半宽格放不下且不长变）、分区表 |
| 内置 / 可拆卸 / 可移除介质 | `is_internal_disk` / `detachable_drive` / `removable_media` | 🆕 | **只取内置** |
| NVMe SMART 深项：已用寿命 / 可用余量 / 通电时长 / 通电次数 / 非正常关机 / 介质错误 / 累计读·写 | 参考项目用自己的 `NVMeSMARTSnapshot` | 🆕 | **取第一梯队**：已用寿命、通电时长、通电次数、累计写入；**舍** 介质错误 / 错误日志（故障诊断向） |
| SATA 专有项（NCQ / 队列深度 / 协商链路速率 / 物理互连） | `SPSerialATADataType` | 🆕 | **舍**（本机 NVMe 不出现；外接 SATA 盘也属低频） |
| 网络卷（挂载来源 / 自动挂载） | `SPNetworkVolumeDataType` | 🆕 | **舍** |
| 读速率 / 写速率 / 已用比例 | 采样器 | ✅ | 运行状态 |

### 3.5 网络（我们的「网络」模块 = 参考项目的 Network 页）

**参考项目**：Network 页 Configuration 卡 + AdapterRow + `NetworkAdapterDetailView` 四段（General / Addresses / Wi-Fi / Traffic）。

| 我们右栏字段 | 来源 | 我们现状 | 决策 |
| --- | --- | --- | --- |
| 接口 / 类型 / 硬件地址 | `SPNetworkDataType` / `SPEthernetDataType` | ✅ `metric.network.ip-address` 等已部分覆盖 | 取 |
| IP 地址 / 子网掩码 / 路由器 / DNS | `SPNetworkDataType` | ✅ IPv4/IPv6；其余 🆕 | 取（IPv4 已有，其余新增） |
| 配置方式 / 接口状态 | `SPNetworkDataType.ConfigMethod` / `IPv4` 段 | 🆕 | 取（配置方式舍，用户不看） |
| 链路速率 / MTU | `SPEthernetDataType` / `CWInterface` | 🆕 | 取链路速率；**舍** MTU |
| Wi-Fi 芯片 | `IODeviceTree:/product` | 🆕 | 取 |
| PHY 模式 / 网络名称 / 频段 / 信道 / 安全 / 国家码 | CoreWLAN `CWInterface` | ✅ SSID/RSSI；其余 🆕 | 取 |
| BSSID | CoreWLAN | 🆕 | **舍**（随漫游变化，对用户无意义） |
| 发射速率 / 发射功率 | CoreWLAN `transmitRate()` | 🆕 | 取发射速率 |
| 信号强度 / 噪声 / 信噪比 | CoreWLAN `rssiValue()` / `noiseMeasurement()` | ✅ RSSI；噪声与信噪比 🆕 | 取 |
| 计算机名 / 服务顺序 / 搜索域 / 代理设置（一大片 `*Enable` / `ExceptionsList`） | `SPNetworkDataType` | 🆕 | **全舍**（代理设置是网络诊断，不属于硬件规格） |
| Traffic：本次会话 / 包数 / 错误 / 冲突 / 丢弃 | 参考项目自己的计数 | 🆕 | **舍** |
| 下行 / 上行速率 | 采样器 | ✅ `metric.network.download` / `.upload` | 已在主列图表 |

### 3.6 电源（我们的「电源」模块）

**参考项目**：硬件页 Power and battery section + 监控页电池轨三卡（Battery health / Electrical / Adapter & power mode）。
**这一块我们已有最多**：`BatterySampler` 已在读 `AppleSmartBattery` 的 CycleCount / DesignCapacity / MaxCapacity / AppleRawMaxCapacity / Voltage / InstantAmperage / Temperature / 电芯电压 / cellQmax / InputVoltage，并已算出健康度。

| 我们右栏字段 | 来源 | 我们现状 | 决策 |
| --- | --- | --- | --- |
| 状态 / 循环次数 / 健康度 / 最大容量 | IOKit `AppleSmartBattery` | ✅ `metric.battery.status` / `.cycle-count` / `.health` / `.capacity` | 取 |
| 设计容量 / 满充容量 | `DesignCapacity` / `AppleRawMaxCapacity` | ✅ 已读（采样器内部） | 取（暴露到右栏） |
| 当前容量 / 电量 / 充电中 | `AppleRawCurrentCapacity` / `kIOPSCurrentCapacityKey` | ✅ 已读 | 取 |
| 电压 / 电流 / 温度 | `AppleRawBatteryVoltage` / `InstantAmperage` / `Temperature` | ✅ `metric.battery.current` / `.temperature` | 取 |
| 电芯电压 / 电芯 Qmax / 电芯平衡 / 内阻 | `AppleSmartBatteryPack` 子节点 | ✅ `metric.battery.cell-*` | 取（这几项我们比参考项目还全） |
| 序列号 / 制造商 / 制造日期 / 电量计芯片 | `AppleSmartBattery` 的 Serial / Manufacturer / ManufactureDate / DeviceName | 🆕 | 取序列号与制造日期；**舍**制造商与电量计 |
| 适配器名称 / 功率 / 端口 / 协商档位 | `AdapterDetails` | ✅ `metric.battery.adapter` / `.adapter-port` / `.pd-tiers` | 取 |
| 适配器输出电压 / 电流 / 充电电流 | `AdapterDetails` | ✅ 部分 | 取 |
| 供电来源 / 低电量模式 | `kIOPSPowerSourceStateKey` / `LowPowerMode` | ✅ `metric.battery.status` | 取 |
| 电源设置（休眠计时 / 网络唤醒 / 休眠模式 / 待机阈值） | `SPPowerDataType` | 🆕 | 取 显示器休眠 / 系统休眠 / 网络唤醒 三项；其余舍 |
| 功耗全表（CPU/GPU/ANE/屏幕/整机 / 热限秒数 / 掉电） | 采样器 | ✅ `metric.battery.*-power` / `.thermal-limit-seconds` / `.power-loss` | **已在面板/供电诊断用，右栏不重复** |

---

## 4. 「本机」10 分类的字段与来源

| # | 我们分类 | 参考项目的对应 section | 主要数据源 | 取/舍要点 |
| --- | --- | --- | --- | --- |
| 1 | **本机** | mac（native identity + `SPHardwareDataType`）；另含 software 的部分 | `IODeviceTree:/product`、`IOPlatformExpertDevice`、`SPHardwareDataType` | 身份类全取：产品名 / 机型标识 / 型号编号 / 序列号 / 硬件 UUID / 监管型号 / 地区 / 原产地 / 制造商 / 系统芯片 / 内存 / 设备树 / 固件版本 / 参考时钟。**舍**：预配 UDID、激活锁、启动 ROM 版本、OS 加载器版本 |
| 2 | **CPU** | processor | 见 3.1 | 见 3.1（指令集特性砍成一行） |
| 3 | **GPU** | graphics | 见 3.2 | 见 3.2（Metal 能力精选四项） |
| 4 | **内存** | memory | 见 3.3 | 见 3.3 |
| 5 | **磁盘** | storage | 见 3.4 | 见 3.4 |
| 6 | **显示器** | displays | `SPDisplaysDataType`（顶层 GPU 项 + `spdisplays_ndrvs` 每屏一个子节点） | 取：芯片组型号 / 厂商 / 核心总数 / Metal 支持 + 每屏 名称 / 像素 / 分辨率 / UI 呈现为 / 类型 / 主显示器 / 在线 / 镜像 / 旋转 / 连接类型 / 位深 / 动态范围 / 序列号 / 厂商 ID / 产品 ID / 制造日期 / 自动调节亮度。**舍**：虚拟设备、Display ID、像素分辨率（参考项目此处是个丑值 `spdisplays_3024x1964Retina`）。**注意**：像素与分辨率是两回事（物理像素 vs UI 逻辑分辨率），两行都要留 |
| 7 | **电源与电池** | power | `AppleSmartBattery` + `SPPowerDataType` | 见 3.6 |
| 8 | **传感器** | sensors | SMC `#KEY` 温度键 + `F0Ac`/`F0Mx`/`FNum` | 取：按域的**每一个可读键**（CPU P/E die / GPU 集群 / SSD / 电池 / 气流 / 机身 / 无线 / 电压轨 / 其他）+ 每域「最热」+ 风扇转速·上限·数量。**注意**：这是我们唯一**实时**的分类（参考项目此处也是静态快照，实时在 Energy 页；我们按实时做，见 README 第 4 节） |
| 9 | **连接** | network + wifi + bluetooth + usb + thunderbolt 五类合并 | `SPNetworkDataType`、`SPEthernetDataType`、CoreWLAN、`SPBluetoothDataType`、`SPUSBHostDataType`、`SPThunderboltDataType` | 见 3.5；蓝牙取 芯片组 / 状态 / 已连接数 / 每设备（名称·类型·电量·固件·厂商 ID·产品 ID·已配对·已配置）；USB 取 设备数 + 每设备（产品名 / 厂商 / 序列号 / 版本 / 链路速率 / 功率分配 / 位置 ID），**舍** 驱动；雷雳取 端口数 / 每端口（状态 / 速率 / 模式 / 链路宽度 / 线缆序列号·固件），**舍** 域 UUID / 路由字符串 / Switch UID |
| 10 | **系统与安全** | software + security（+ secure element）三合一 | `SPSoftwareDataType`、sysctl、`SPiBridgeDataType`、`SPSecureElementDataType` | 取：系统版本 / Darwin 版本 / 内核 / 内核类型 / 主机名 / 上次启动 / 运行时长 / 启动参数 / 安全模式 / 安全内核 / 最大进程数·打开文件数 / Rosetta 2 / 活动处理器数 + 安全启动 / SIP / 签名系统卷 / 内核 CTRR / 设备 MDM / 手动 MDM / 用户批准的内核扩展 / 启动 UUID / 构建版本 + 安全隔区（设备 / 固件 / 硬件 / ID / 限制模式 / 系统版本 / 平台 / 生产签名）。**舍**：安全隔区的 Info 段 |

---

## 5. 参考项目 20 类 → 我们 10 类的合并对照

| 参考项目分类 | 我们的归处 |
| --- | --- |
| mac | 本机 |
| processor | CPU |
| graphics | GPU |
| memory | 内存 |
| displays | 显示器 |
| storage | 磁盘 |
| power | 电源与电池 |
| sensors | 传感器 |
| network + wifi | 连接（网络接口段 / Wi-Fi 段） |
| bluetooth + usb + thunderbolt | 连接（各自一段） |
| software + security | 系统与安全 |
| **audio** | **删**（音频设备对硬件规格档价值低） |
| **cameras** | **删** |
| **pci** | **删**（Apple Silicon 上信息极少） |
| **peripherals**（SPI / 读卡器 / 智能卡） | **删** |
| **printers** | **删** |
| **Overview（概览九卡）** | **删**——其内容与本机 10 分类重复；身份信息放「本机」分类 |

**净结果**：20 类 → 10 类，砍掉 5 个低频分类 + 1 个重复的概览屏。

---

## 6. 命名与缺失语义

- **分类名**复用现有常量：`kind.cpu` / `kind.gpu` / `kind.memory` / `kind.storage`(=磁盘) / `kind.display` / `kind.battery`(=电源) / `kind.network` / `kind.bluetooth`；新增 `kind.sensors` / `kind.system` 与模块名 `kind.thisMac`（「本机」）。
- **字段标签**优先复用 `metric.*`：`metric.cpu.*` / `metric.gpu.*` / `metric.memory.*` / `metric.storage.*` / `metric.display.*` / `metric.battery.*` / `metric.network.*`；新增按 `metric.<module>.<field>`。
- **值要翻译**（与参考项目相反）：枚举值（是/否、内置/外接、已验证…）走 `Localizable.xcstrings` 中英两语，不沿用它的「值永不翻译」。
- **缺失显示 `—`**，不推断为 0 或「正常」——沿用面板 `DisplayArchiveTile` 的既有取舍。
- **半宽格值预算**：参考面板档案的做法，值超预算升为整行；序列号、主机名、DNS 这类按这个规则处理。

---

## 7. 明确不照抄参考项目的四处

1. **不做 root 特权辅助进程**。它用 `SMAppService.daemon` + XPC 补读系统进程的 CPU/唤醒数；我们 App Store 渠道不可分发。
2. **不把整机负载按估分摊给应用**（分应用能耗那条线同理，见 `per-process-energy-attribution`）。
3. **值要本地化**，不学它「值永不翻译」。
4. **传感器做实时**：它只在概览卡里 5s 节流扫一次、其余是静态快照；我们按「本机 → 传感器」实时（README 第 4 节）。

---

## 9. 本机实测（2026-09-12，Mac16,1 / Apple M4 / macOS 27.0 (26A428)）

探针在 `tmp/hw-probe/`（`smc-probe.swift` / `dt-probe.sh` / `deep.py` / `deep2.py` / `fan.swift`），只读。

### 9.1 SMC：温度键与风扇（回答「传感器分类件数」）

- SMC 键总数 `#KEY` = **2806**
- `T*` 键共 **222** 个，其中**可读（1–130 °C）187 个**，35 个不可读（值 0 或类型解析不出）

| 域 | 实测键数 | 最热 / 最低 |
| --- | --- | --- |
| CPU 性能核 die (`Tp`) | **39** | 85.9 / 50.8 °C |
| CPU 能效核 die (`Te`) | **16** | 60.1 / 46.4 °C |
| GPU 集群 (`Tg`) | **18** | 55.3 / 46.6 °C |
| 机身与主板 (`Ts`/`Th`) | **28** | 51.9 / 30.4 °C |
| 电压轨 (`TV`) | **10** | 61.4 / 24.5 °C |
| 存储 · 电池 · 气流 (`TH0`) | **3** | 36.9 / 35.1 °C |
| 电池 (`TB`) | **3** | 32.8 / 32.7 °C |
| 气流 (`Ta`，排除 `Ta0`) | **2** | 34.0 / 33.6 °C |
| 无线 (`TW`) | **1** | 41.0 °C |
| **其他（域表未覆盖）** | **67** | 85.9 / 6.2 °C |

**结论：域表要扩。** 参考项目的 10 个域盖不住这台机器——**67 个键（占可读的 36%）落在「其他」**，主要是 `TPD*`(18 个) / `TD*`(22) / `TRD*`(10) / `TSCD` / `TAOL` / `TCHP` / `TCM*` / `TIOP` / `TMVR` / `TPMP` / `TfC*` 等新机型键。
实际做法建议：**域表保持参考项目那 10 个（用户认得的语义域），「其他」不铺 67 行**，而是在该域只显示「N 个传感器 · 最热 X °C」，点开再看全量键（参考项目在 Overview 卡上正是这么做的）。
另外**项目现有 `SMCReader.temperatureKeys` 硬编码 10 个键（Tp09/Tp0T/Tp01/Tp05/Tp0D/Tp0H/Tp0L/Tp0P/Tp0X/Tp0b），本机实测只有 6 个存在**（缺 `Tp0T` `Tp0H` `Tp0L` `Tp0P`）——硬件页应改用实测全表，别沿用这份硬编码。

**风扇实测**：`FNum` = 1（1 个风扇）；`F0Mn` = 2317、`F0Mx` = 6550（**可读**）；**`F0Ac` = 0.0（类型 `flt`，字节全 0）——风扇当前停转**。
这不等于「读不到」：0 是**真实读数**。所以风扇行要区分三种态：**停转（0） / 转速（>0） / 不可读（键缺失）**；项目现有 `maxFanRPM()` 把 0 与失败一起归为 nil（面板降级为 unavailable），硬件页应改进这个语义。

**顺带实测到的其它 SMC 键**：`PSTR`（整机功耗，flt，本机 ≈ 8.1 W）可读、`PDTR`（DC 输入，≈ 0）可读、`TPMP`（≈ 42 °C）可读。

### 9.2 system_profiler：16 个 DataType 的真实返回

**全部 16 个跑完约 2.1 秒**（单个 0.07–0.18 s），比预期的「数百毫秒×16」便宜得多，一次性读取的代价可以忽略。

| DataType | 实测 | 结论 |
| --- | --- | --- |
| `SPHardwareDataType` | 1 项 / 13 字段 | 取。真实值：芯片 Apple M4、机型 `Mac16,1`、型号编号 `Z1JS000HLCH/A`、`number_processors = "proc 10:0:4:6"`、内存 32 GB |
| `SPMemoryDataType` | 1 项 / **3 字段** | **不要删——不是空的**：`dimm_type = LPDDR5`、`dimm_manufacturer = Hynix`、`SPMemoryDataType = 32 GB`。只取「类型」一项（合并成「LPDDR5 · Hynix」），容量走 `hw.memsize` |
| `SPDisplaysDataType` | 1 项（GPU）/ 每屏在 `spdisplays_ndrvs` | 取。本机内置 1 台：`_spdisplays_pixels = 3024 x 1964`、`_spdisplays_resolution = "1512 x 982 @ 60.00Hz"`（**刷新率在这个字符串里**）、`spdisplays_display_type = spdisplays_built-in-liquid-retina-xdr`、`spdisplays_pixelresolution = spdisplays_3024x1964Retina`（丑值，删） |
| `SPStorageDataType` | **2 项**（2 个卷） | 取。`physical_drive` 只有 `device_name/is_internal_disk/media_name/medium_type/partition_map_type/protocol/smart_status` —— **型号/序列号/固件不在这里**，要从 `SPNVMeDataType` 取 |
| `SPNVMeDataType` | 1 项 → `_items[0]` | 取。真实值：`device_model = APPLE SSD AP1024Z`、`device_revision = 241.0.12`、`device_serial = 0ba0288c0128c43a`、`size = 1 TB`、`size_in_bytes = 1000555581440`、`smart_status = Verified`、`spnvme_trim_support = Yes`；子项 `volumes` 3 个 |
| `SPSerialATADataType` | **0 项** | 本机不出现 → **确认舍** |
| `SPNetworkVolumeDataType` | 1 项 | 网络卷（`automounted`/`fsmtnonname`/`fstypename`/`mntfromname`）→ **确认舍** |
| `SPPowerDataType` | **4 项** | 取。结构：`spbattery_information`（charge/health/model 三个子字典）、**`sppower_information`（`AC Power` 与 `Battery Power` 两个子字典 = 电源设置）**、`sppower_hwconfig_information`、`sppower_ac_charger_information` |
| `SPNetworkDataType` | **5 项**（5 个网络服务） | 取。每项含 `interface`/`hardware`/`IPv4`/`IPv6`/`Proxies`/`spnetwork_service_order`/`type` 等嵌套字典 |
| `SPEthernetDataType` | **0 项** | 本机无有线接口 → 保留读取但按缺失处理 |
| `SPBluetoothDataType` | 1 项 | 取。`controller_properties` + `device_connected` + `device_not_connected` |
| `SPUSBHostDataType` | **3 项**（3 条总线） | 取。**设备在总线项的 `_items` 里**，本机只在第 3 条总线上有 1 个设备（`Wireless Receiver`），字段：`USBDeviceKeyProductID`/`VendorID`/`VendorName`/`SerialNumber`/`ProductVersion`/`LinkSpeed` + `USBKeyHardwareType`/`LocationID` → **USB 单列到设备层可行** |
| `SPUSBDataType` | **0 项** | 证实必须读 `USBHostDataType`（macOS 26+ 换了名字），`USBDataType` 只作旧系统回退 |
| `SPThunderboltDataType` | **3 项**（3 条总线） | 取。**端口信息在 `receptacle_N_tag` 字典里**：`current_speed_key`（本机 `Up to 40 Gb/s`）/ `link_status_key`（`0x100`）/ `receptacle_id_key`（4、2、1）/ `receptacle_status_key`（本机均为 `receptacle_no_devices_connected`）→ **本机 3 个雷雳端口可单列** |
| `SPiBridgeDataType` | 1 项 / 12 字段 | 取：`ibridge_secure_boot` / `ibridge_sb_sip` / `ibridge_sb_ssv` / `ibridge_sb_ctrr` / `ibridge_sb_device_mdm` / `ibridge_sb_manual_mdm` / `ibridge_sb_other_kext` / `ibridge_boot_uuid` / `ibridge_build` / `ibridge_sb_boot_args` / `ibridge_extra_boot_policies` / `ibridge_model_identifier_top` |
| `SPSecureElementDataType` | 1 项 / 14 字段 | 取：`se_device` / `se_fw` / `se_hw` / `se_id` / `se_in_restricted_mode` / `se_os_id` / `se_os_version` / `se_plt` / `se_prod_signed` + `ctl_fw` / `ctl_hw` / `ctl_mw` / `ctl_info` / `se_info` |
| `SPSoftwareDataType` | 1 项 / 10 字段 | 取。真实值：`os_version = "macOS 27.0 (26A428)"`、`kernel_version = "Darwin 27.0.0"`、`boot_volume = Macintosh HD`、`boot_mode = normal_boot`、`system_integrity = integrity_enabled`、`secure_vm = secure_vm_enabled`、`local_host_name`、`user_name`、`uptime = "up 2:5:45:42"` |

**实测修正的 4 处猜测**：① `SPMemoryDataType` 不是空的（LPDDR5 / Hynix 可读）→ 内存分类保留「类型」；② 显示器 `_spdisplays_display-week`/`-year` 本机都是 **0** → **制造日期是缺失值**，不是「2025 年第 32 周」（我原先夹具里是编的）；③ 位深 / 色域 / 动态范围**不在** `SPDisplaysDataType` 里 → 走我们已有的 `DisplayTelemetryReader`；④ 磁盘的型号/序列号/固件**不在** `SPStorageDataType.physical_drive` 里，只在 `SPNVMeDataType`。

### 9.3 两个采集侧的硬约束（落地前必须定）

**① SMC 在 App Store 版读不到——`Entitlements` 里没有 IOKit 权限。**
`HagimiMonitor.entitlements` 只有 `app-sandbox` + `device.bluetooth` + `network.client`，而 `SMCReader.init?()` 靠 `IOServiceOpen(AppleSMC)`——沙盒下被拒（项目 `FanSampler` 的注释已经写明，且从 entitlements 也能确认）。实测我是在**非沙盒的 CLI** 下跑的，所以数据是真的，但那只对应 **Direct 渠道**。
影响：**「本机 → 传感器」分类（温度域 + 风扇）在 App Store 版基本为空**。可选处理：
- a. 传感器分类只出现在 Direct 版；App Store 版该分类显示「当前渠道不可读」（与既有「不伪造数值」一致）
- b. 传感器分类在 App Store 版只留 **GPU 温度/时钟态**（走 `IOAccelerator`，非 SMC）+ 热压力（`ProcessInfo.thermalState`），其余标注不可读
- c. 本机模块整体只在 Direct 版出现

**② NVMe SMART 深项需要额外的 C shim，且沙盒可行性未知。**
`SPNVMeDataType` **不含** 已用寿命 / 通电时长 / 通电次数 / 非正常关机 / 介质错误——参考项目是走 `IONVMeSMARTUserClient` plug-in 接口读 **512 字节 SMART/Health log page**（NVMe 规范图 194），且它的注释明确说「COM 式 plug-in 调用 Swift 写不了」，所以用了 C shim（`CMacPerfMonitor/shim.c`）。参考项目**不在沙盒里**；我们的沙盒版能否调用该 user client **未验证**，需要先写个最小探针确认。
好消息：**累计读·写不需要它**——`StorageSampler` 已经在读 `IOBlockStorageDriver` 的统计（`cumulativeBytesRead` / `cumulativeBytesWritten`）。所以「第一梯队」里只有 已用寿命 / 通电时长 / 通电次数 / 非正常关机 依赖 SMART log。

### 9.4 落地顺序建议

1. **先做不依赖特权的一层**：16 个 DataType（约 2 秒一次性读）+ sysctl + `IODeviceTree`/`IOPlatformExpertDevice` + Metal + CoreWLAN + 已有的 `IOBlockStorageDriver` 统计 → 这一层就能填满 `本机` 10 分类里除「传感器」与「SMART 深项」之外的全部，以及六个模块右栏的静态规格组。
2. **再补模块块的模板改造**（`.module-block` + 右栏 + 本机分类菜单）——版面不依赖上面那层是否完整，可以并行。
3. **最后处理两个受限期**：先写 C shim 探针验证沙盒下的 NVMe SMART；SMC 按 ①. a 或 b 的方案定。

---

## 10. 落地进度（2026-09-12 已实现并集成）

设计已按本文件的映射落进产品代码,不再是原型:

| 部分 | 位置 | 状态 |
| --- | --- | --- |
| 采集器 | `HagimiMonitor/Hardware/`（Models / Sysctl / IOKit / SystemProfilerRunner / InventoryReader / InventoryReaderComponents / LiveReadings） | 10 分类全部实现,8 个测试（`HardwareInventoryReaderTests`） |
| 载荷 | `StatisticsReportBuilder.payloadJSON` 的 `hardware` 段（分类 → 分组 → 规格行,缺失编成 `null`） | 生成报表时在后台任务里一次性采集 |
| 版面 | `HagimiMonitor/Resources/HardwareSection.{css,js}`，由生成器内联进模板（与 ECharts/Flatpickr 同一机制） | 模块块 + 右栏规格 + 本机分类菜单 |
| 实时 | `HardwareLiveReadings` + `ReportWindowPresenter` 的 1 秒定时器 | 只推「运行状态」组,窗口被遮挡即停 |

**实际落地的取舍**（与本文件前面的建议有出入的地方,以这里为准）:

- **传感器分类只在直连版出现**——不是靠 `#if`,而是「SMC 读不到 → 分类不生成」,沙盒版自然没有这一类。
- **NVMe SMART 深项未做**。它要 `IONVMeSMARTUserClient` 这个 IOKit user client(参考项目为此写了 C shim),而我们的沙盒渠道没有 IOKit 权限、直连版也需额外验证;**磁盘的累计读·写改走已有的 `IOBlockStorageDriver` 统计**(两渠道都有)。这一项是唯一明确未落地的字段组。
- **GPU 的 Metal 能力只留 5 项**(统一内存 / 推荐工作集 / 最大缓冲 / 光线追踪 / 32 位 MSAA / BC 纹理压缩 / 函数指针),不做参考项目那 30 多项的开发者清单。
- **神经网络引擎未列**：`IODeviceTree:/arm-io/ane` 在本机不暴露可读的核数(参考项目是硬编码芯片→核数表),宁可缺也不硬编码。
- **安全隔区只留可读的控制器版本号**：`se_device` / `se_fw` / `se_hw` / `se_plt` 实测是十六进制寄存器值与不透明 ID,不列。
- **字节格式化两套**:缓存/页大小/内存用 1024 进制(与 macOS 文案一致),磁盘/卷容量用 1000 进制(厂商口径)。

**集成时踩到并修掉的坑**(都写进了代码注释):

1. **不能假定 sysctl 键宽度**：`hw.perflevel{n}` 的缓存键是 4 字节,`hw.cachelinesize` 是 8 字节;按固定宽度读会让整组缓存为空。
2. **`SPiBridgeDataType` 的值系统已本地化**(中文系统下就是「已启用」),而 `SPSoftwareDataType.boot_mode` 不本地化;不能一刀切写枚举映射。
3. **把板块搬进模块块时必须先插块、再搬节点**,否则 `insertBefore` 报「新子节点包含父节点」,板块会被搬离文档、整块模块消失。
4. **swift-testing 默认并行跑用例**：每个用例都触发一次采集时会互抢 system_profiler,导致部分 DataType 超时返空——套件必须 `.serialized`。

### 待确认（更新）

- NVMe SMART 深项要不要补(C shim + 沙盒可行性验证)。
- 「N 项」这类页头计数文案要不要进一步收敛。
- 传感器分类目前是**打开报表时的快照**;要不要连它一起做实时(需要每域挑代表键,而不是每秒全量扫 2800 个键)。


- **SMC 的渠道方案**（9.3 ①）：传感器分类走 a / b / c 哪一种。
- **NVMe SMART 是否本轮做**（9.3 ②）：要先验证沙盒可行性，还是先落「累计读·写 + SMART 状态」。
- 「其他」温度域（67 个键）按「N 个传感器 · 最热 X °C + 点开看全量」折叠，是否接受。
- 风扇行区分「停转 / 转速 / 不可读」三态，面板那边要不要一起改（现在 0 与失败都归 unavailable）。

