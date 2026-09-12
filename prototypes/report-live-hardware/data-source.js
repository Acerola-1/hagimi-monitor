/* 数据来源标注:实现阶段直接对着看。
   st 三档 —— ok = 本项目已在读 / new = 需新读 / mix = 混合(见该组的行级覆盖)
   粒度:分组级为主,只在「同一组里状态不同」的关键行做行级覆盖。
   完整逐字段表见 HARDWARE-DATA-MAP.md。 */
const SOURCES = {
  /* ── 六个监控模块的右栏 ── */
  cpu: {
    groups: {
      '芯片与架构': { src: 'sysctl machdep.cpu.* / hw.perflevel{n}.* / hw.cachesize', st: 'mix' },
      '运行状态': { src: '采样器 + sysctl kern.boottime', st: 'ok' },
    },
    rows: {
      '芯片与架构|芯片': { src: 'sysctl machdep.cpu.brand_string(UsageReporter 已在读)', st: 'ok' },
      '芯片与架构|CPU 家族': { src: 'sysctl hw.cpufamily', st: 'new' },
    },
  },
  gpu: {
    groups: {
      '图形与 Metal': { src: 'MTLDevice + IOKit AGXAccelerator + SPDisplaysDataType', st: 'new' },
      '神经网络引擎': { src: 'IODeviceTree:/arm-io/ane', st: 'new' },
      '运行状态': { src: '采样器(IOReport) + SMC', st: 'ok' },
    },
  },
  memory: {
    groups: {
      '容量与类型': { src: 'sysctl hw.memsize / hw.pagesize + SPMemoryDataType', st: 'mix' },
      '运行状态': { src: '采样器', st: 'ok' },
    },
    rows: {
      '容量与类型|总容量': { src: 'metric.memory.total', st: 'ok' },
      '容量与类型|内存带宽': { src: 'metric.memory.memory-bandwidth', st: 'ok' },
      '容量与类型|内存类型': { src: 'SPMemoryDataType.dimm_type(Apple Silicon 常为空)', st: 'new' },
    },
  },
  disk: {
    groups: {
      '卷': { src: 'SPStorageDataType', st: 'new' },
      '物理驱动器': { src: 'SPNVMeDataType + StorageSMARTProbe', st: 'mix' },
      '运行状态': { src: '采样器', st: 'ok' },
    },
    rows: {
      '物理驱动器|SMART 状态': { src: 'metric.storage.smart(StorageSMARTProbe 已在读)', st: 'ok' },
      '物理驱动器|TRIM 支持': { src: 'SPNVMeDataType.spnvme_trim_support', st: 'new' },
    },
  },
  network: {
    groups: {
      '接口与配置': { src: 'SPNetworkDataType + SPEthernetDataType', st: 'mix' },
      'Wi-Fi': { src: 'CoreWLAN CWInterface + IODeviceTree:/product', st: 'mix' },
      '运行状态': { src: 'CoreWLAN + 采样器', st: 'mix' },
    },
    rows: {
      '接口与配置|接口': { src: 'metric.network.ip-address 同源', st: 'ok' },
      '接口与配置|IP 地址': { src: 'metric.network.ipv4', st: 'ok' },
      '接口与配置|DNS': { src: 'SPNetworkDataType.dhcp_domain_name_servers', st: 'new' },
      'Wi-Fi|网络名称': { src: 'CoreWLAN SSID(WiFiProbe 已在读)', st: 'ok' },
      'Wi-Fi|Wi-Fi 芯片': { src: 'IODeviceTree:/product', st: 'new' },
      '运行状态|信号强度': { src: 'metric.network.wifi-rssi(WiFiProbe 已在读)', st: 'ok' },
      '运行状态|噪声': { src: 'CoreWLAN noiseMeasurement()', st: 'new' },
    },
  },
  power: {
    groups: {
      '电池': { src: 'IOKit AppleSmartBattery / AppleSmartBatteryPack', st: 'mix' },
      '电源适配器': { src: 'IOKit AdapterDetails', st: 'ok' },
      '电源设置': { src: 'SPPowerDataType', st: 'new' },
      '运行状态': { src: '采样器(metric.battery.*)', st: 'ok' },
    },
    rows: {
      '电池|序列号': { src: 'AppleSmartBattery.Serial(采样器未暴露)', st: 'new' },
      '电池|制造日期': { src: 'AppleSmartBattery.ManufactureDate', st: 'new' },
      '电池|状态': { src: 'metric.battery.status', st: 'ok' },
      '电池|循环次数': { src: 'metric.battery.cycle-count', st: 'ok' },
      '电池|最大容量': { src: 'metric.battery.capacity', st: 'ok' },
    },
  },

  /* ── 本机 10 分类 ── */
  'm-self': {
    groups: {
      '身份': { src: 'IOPlatformExpertDevice + SPHardwareDataType', st: 'new' },
      '芯片与内存': { src: 'IODeviceTree:/product + sysctl hw.memsize', st: 'new' },
      '其他能力': { src: 'IODeviceTree:/product', st: 'new' },
    },
    rows: { '身份|机型标识': { src: 'sysctl hw.model(报表已在读)', st: 'ok' } },
  },
  'm-cpu': {
    groups: {
      '处理器': { src: 'sysctl machdep.cpu.* / hw.*', st: 'mix' },
      '性能核': { src: 'sysctl hw.perflevel0.*', st: 'new' },
      '能效核': { src: 'sysctl hw.perflevel1.*', st: 'new' },
      '指令集特性': { src: 'sysctl hw.optional.*(建议砍成一行,参考项目列 60+ 项)', st: 'new' },
    },
    rows: { '处理器|芯片': { src: 'sysctl machdep.cpu.brand_string', st: 'ok' } },
  },
  'm-gpu': {
    groups: {
      '图形处理器': { src: 'MTLDevice + SPDisplaysDataType.sppci_cores', st: 'new' },
      'Metal 特性': { src: 'MTLDevice.supports*(建议只留光线追踪/32 位 MSAA/BC 纹理压缩/读写纹理)', st: 'new' },
      '神经网络引擎': { src: 'IODeviceTree:/arm-io/ane', st: 'new' },
    },
  },
  'm-memory': {
    groups: {
      '容量与类型': { src: 'sysctl hw.memsize / hw.pagesize / hw.optional.ecc + SPMemoryDataType', st: 'mix' },
      '运行状态': { src: '采样器(metric.memory.*)', st: 'ok' },
    },
    rows: {
      '容量与类型|已安装': { src: 'metric.memory.total(实测 hw.memsize = 32 GB)', st: 'ok' },
      '容量与类型|类型': { src: 'SPMemoryDataType.dimm_type 实测 "LPDDR5" —— 不是空的,保留', st: 'new' },
      '容量与类型|制造商': { src: 'SPMemoryDataType.dimm_manufacturer 实测 "Hynix"', st: 'new' },
      '容量与类型|内存带宽': { src: 'metric.memory.memory-bandwidth', st: 'ok' },
    },
  },
  'm-disk': {
    groups: {
      '卷 · Macintosh HD': { src: 'SPStorageDataType(实测 2 个卷)', st: 'new' },
      '卷 · Data': { src: 'SPStorageDataType', st: 'new' },
      '物理驱动器': { src: 'SPNVMeDataType._items(型号/固件/序列号只在这里,physical_drive 里没有)', st: 'mix' },
      'SMART 深项': { src: 'IONVMeSMARTUserClient 读 512B SMART/Health log page(需 C shim) · 累计读·写可改走已有 IOBlockStorageDriver 统计', st: 'new' },
      '运行状态': { src: '采样器 · 累计读写已是 StorageSampler 的 cumulativeBytesRead/Written', st: 'ok' },
    },
    rows: { '物理驱动器|SMART 状态': { src: 'metric.storage.smart(实测 smart_status = Verified)', st: 'ok' } },
  },
  'm-display': {
    groups: {
      '图形芯片组': { src: 'SPDisplaysDataType(顶层 GPU 项)', st: 'new' },
      '内置显示器（本机 1 台；多屏时按屏重复此组）': { src: 'SPDisplaysDataType.spdisplays_ndrvs(实测本机 1 台)', st: 'mix' },
      '来自我们已有读取（不在 SPDisplaysDataType 里）': { src: 'DisplayTelemetryReader(CoreGraphics)', st: 'ok' },
    },
    rows: {
      '内置显示器（本机 1 台；多屏时按屏重复此组）|制造日期': { src: '_spdisplays_display-year/week 实测都是 0 → 缺失,按 — 显示', st: 'na' },
      '内置显示器（本机 1 台；多屏时按屏重复此组）|分辨率': { src: '_spdisplays_resolution = "1512 x 982 @ 60.00Hz"(刷新率在这个字符串里)', st: 'new' },
      '内置显示器（本机 1 台；多屏时按屏重复此组）|序列号': { src: '_spdisplays_display-serial-number,fmtRPM 之外不本地化', st: 'new' },
    },
  },
  'm-power': {
    groups: {
      '电池': { src: 'IOKit AppleSmartBattery', st: 'mix' },
      '电源适配器': { src: 'IOKit AdapterDetails', st: 'ok' },
      '电源设置': { src: 'SPPowerDataType', st: 'new' },
      '运行状态': { src: '采样器(metric.battery.*)', st: 'ok' },
    },
    rows: {
      '电池|循环次数': { src: 'metric.battery.cycle-count', st: 'ok' },
      '电池|设计容量': { src: 'AppleSmartBattery.DesignCapacity(BatterySampler 已读)', st: 'ok' },
      '电池|序列号': { src: 'AppleSmartBattery.Serial', st: 'new' },
      '电池|制造日期': { src: 'AppleSmartBattery.ManufactureDate', st: 'new' },
      '电池|温度': { src: 'metric.battery.temperature', st: 'ok' },
    },
  },
  'm-sensors': {
    groups: {
      'CPU 性能核 die · 39 个': { src: 'SMC #KEY 前缀 Tp · 本机实测 39 个可读', st: 'ok' },
      'CPU 能效核 die · 16 个': { src: 'SMC #KEY 前缀 Te · 实测 16 个', st: 'ok' },
      'GPU 集群 · 18 个': { src: 'SMC #KEY 前缀 Tg · 实测 18 个', st: 'ok' },
      '机身与主板 · 28 个': { src: 'SMC #KEY 前缀 Ts · Th · 实测 28 个', st: 'ok' },
      '电压轨 · 10 个': { src: 'SMC #KEY 前缀 TV · 实测 10 个', st: 'ok' },
      '存储 · 电池 · 气流': { src: 'SMC TH0A / TB0T / TaLR · 实测各 1–3 个', st: 'ok' },
      '其他 · 67 个（未归类键）': { src: 'SMC TPD*/TD*/TRD* 等新机型键 · 建议只显示计数与最热,不铺开', st: 'ok' },
      '风扇': { src: 'SMC FNum / F0Ac / F0Mn / F0Mx(FanSampler 已在读) · 0 = 停转,不是缺失', st: 'ok' },
    },
    rows: {
      '风扇|风扇 1': { src: 'SMC F0Ac · 实测本机 0.0(停转)。注意现有 maxFanRPM() 把 0 与失败同归 nil', st: 'ok' },
    },
  },
  /* ⚠ SMC 整类仅在 Direct 渠道可读:entitlements 无 IOKit,沙盒下 IOServiceOpen(AppleSMC) 被拒。
     App Store 版建议只留 GPU 温度/时钟态(走 IOAccelerator)+ 热压力(ProcessInfo.thermalState)。 */
  'm-connect': {
    groups: {
      '网络接口': { src: 'SPNetworkDataType(实测 5 个服务,含 interface/hardware/IPv4/IPv6 嵌套)', st: 'mix' },
      'Wi-Fi': { src: 'CoreWLAN CWInterface', st: 'mix' },
      '蓝牙': { src: 'SPBluetoothDataType(controller_properties + device_connected)', st: 'mix' },
      'USB（3 条总线 · 本机 1 台设备）': { src: 'SPUSBHostDataType._items(实测 3 条总线,设备挂在 _items 里)', st: 'new' },
      '雷雳 / USB4（3 个端口）': { src: 'SPThunderboltDataType.receptacle_N_tag(实测 3 个端口)', st: 'new' },
    },
    rows: {
      '网络接口|IP 地址': { src: 'metric.network.ipv4 / .ipv6', st: 'ok' },
      'Wi-Fi|网络名称': { src: 'WiFiProbe(已在读)', st: 'ok' },
      'Wi-Fi|信号强度': { src: 'metric.network.wifi-rssi', st: 'ok' },
      'USB（3 条总线 · 本机 1 台设备）|总线 1': { src: 'SPUSBHostDataType(第 3 条总线才有 _items)', st: 'new' },
    },
  },
  'm-system': {
    groups: {
      '系统': { src: 'SPSoftwareDataType + sysctl kern.*', st: 'mix' },
      '安全': { src: 'SPiBridgeDataType(实测 12 字段)', st: 'new' },
      '安全隔区': { src: 'SPSecureElementDataType(实测 14 字段)', st: 'new' },
    },
    rows: {
      '系统|运行时长': { src: 'metric.cpu.uptime', st: 'ok' },
      '系统|系统版本': { src: 'SPSoftwareDataType.os_version(实测 "macOS 27.0 (26A428)")', st: 'new' },
      '系统|内核': { src: 'SPSoftwareDataType.kernel_version(实测 "Darwin 27.0.0")', st: 'new' },
    },
  },
};

/* 分组级来源;没有登记的分组返回 null(不显示来源标签) */
function sourceFor(id, groupName) {
  return (SOURCES[id] && SOURCES[id].groups && SOURCES[id].groups[groupName]) || null;
}
function sourceForRow(id, groupName, label) {
  return (SOURCES[id] && SOURCES[id].rows && SOURCES[id].rows[`${groupName}|${label}`]) || null;
}
